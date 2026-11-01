"""ResumeLens UI used by the API and local Case Study 3 containers."""

from __future__ import annotations

import os
import time
from functools import lru_cache

import gradio as gr
import torch
from huggingface_hub import InferenceClient
from prometheus_client import Counter, Gauge, Histogram, start_http_server
from transformers import AutoModelForCausalLM, AutoTokenizer


PRODUCT_MODE = os.getenv("PRODUCT_MODE", "api").strip().lower()
if PRODUCT_MODE not in {"api", "local"}:
    raise RuntimeError("PRODUCT_MODE must be either 'api' or 'local'")

PRODUCT_NAME = f"resumelens_{PRODUCT_MODE}"
ROOT_PATH = os.getenv("ROOT_PATH", f"/{PRODUCT_MODE}")
REMOTE_MODEL = os.getenv("REMOTE_MODEL", "openai/gpt-oss-20b")
LOCAL_MODEL = os.getenv("LOCAL_MODEL", "Qwen/Qwen3-0.6B")
HF_TOKEN = os.getenv("HF_TOKEN", "").strip()
MAX_NEW_TOKENS = int(os.getenv("MAX_NEW_TOKENS", "512"))


# Eight product metrics. The fixed product/model labels keep cardinality bounded.
REQUESTS = Counter(
    "resumelens_requests_total",
    "Completed ResumeLens review requests",
    ["product", "result"],
)
REQUEST_DURATION = Histogram(
    "resumelens_request_duration_seconds",
    "End-to-end review latency",
    ["product"],
    buckets=(0.5, 1, 2, 5, 10, 20, 40, 80, 160),
)
IN_PROGRESS = Gauge(
    "resumelens_in_progress_requests",
    "Reviews currently executing",
    ["product"],
)
INPUT_CHARACTERS = Histogram(
    "resumelens_input_characters",
    "Resume and job-description input size",
    ["product"],
    buckets=(100, 500, 1000, 2500, 5000, 10000, 20000),
)
OUTPUT_CHARACTERS = Histogram(
    "resumelens_output_characters",
    "Generated review size",
    ["product"],
    buckets=(100, 500, 1000, 2500, 5000, 10000),
)
MODEL_CALLS = Counter(
    "resumelens_model_calls_total",
    "Model calls attempted",
    ["product", "model"],
)
ERRORS = Counter(
    "resumelens_errors_total",
    "Review failures by bounded error category",
    ["product", "error_type"],
)
BUILD_INFO = Gauge(
    "resumelens_build_info",
    "Static application build information",
    ["product", "model", "version"],
)

ACTIVE_MODEL = REMOTE_MODEL if PRODUCT_MODE == "api" else LOCAL_MODEL
BUILD_INFO.labels(PRODUCT_NAME, ACTIVE_MODEL, "cs3-v1").set(1)


SYSTEM_PROMPT = """You are ResumeLens, a careful resume-review assistant.
Compare only the supplied resume and job description. Do not invent experience,
credentials, employers, dates, or skills. Organize the answer into:
1. Requirements supported
2. Requirements partially supported
3. Requirements not evident
4. Existing experience to emphasize
5. Three specific, truthful edits
State clearly when evidence is missing. Do not expose private contact details."""


def _messages(resume: str, job_description: str, focus: str) -> list[dict[str, str]]:
    prompt = f"""Review the following sanitized resume against the job description.

FOCUS: {focus}

RESUME:
{resume.strip()}

JOB DESCRIPTION:
{job_description.strip()}
"""
    return [
        {"role": "system", "content": SYSTEM_PROMPT},
        {"role": "user", "content": prompt},
    ]


@lru_cache(maxsize=1)
def _load_local_model():
    """Load once, on the first local request, instead of during container startup."""
    tokenizer = AutoTokenizer.from_pretrained(LOCAL_MODEL)
    model = AutoModelForCausalLM.from_pretrained(
        LOCAL_MODEL,
        torch_dtype="auto",
    )
    model.to("cpu")
    model.eval()
    return tokenizer, model


def _local_review(messages: list[dict[str, str]]) -> str:
    tokenizer, model = _load_local_model()
    encoded = tokenizer.apply_chat_template(
        messages,
        add_generation_prompt=True,
        return_tensors="pt",
    ).to(model.device)
    with torch.inference_mode():
        generated = model.generate(
            encoded,
            max_new_tokens=MAX_NEW_TOKENS,
            do_sample=False,
            repetition_penalty=1.05,
            pad_token_id=tokenizer.eos_token_id,
        )
    new_tokens = generated[0, encoded.shape[-1] :]
    return tokenizer.decode(new_tokens, skip_special_tokens=True).strip()


def _api_review(messages: list[dict[str, str]]) -> str:
    if not HF_TOKEN:
        raise RuntimeError("missing_hf_token")
    client = InferenceClient(token=HF_TOKEN)
    response = client.chat_completion(
        model=REMOTE_MODEL,
        messages=messages,
        max_tokens=MAX_NEW_TOKENS,
        temperature=0.2,
    )
    return (response.choices[0].message.content or "").strip()


def _error_category(exc: Exception) -> str:
    if isinstance(exc, ValueError):
        return "validation"
    text = str(exc).lower()
    if "missing_hf_token" in text:
        return "configuration"
    if "timeout" in text:
        return "timeout"
    if "401" in text or "403" in text or "unauthorized" in text:
        return "authentication"
    if "429" in text or "rate" in text:
        return "rate_limit"
    return "inference"


def review_resume(resume: str, job_description: str, focus: str) -> str:
    resume = resume or ""
    job_description = job_description or ""
    input_size = len(resume) + len(job_description)
    INPUT_CHARACTERS.labels(PRODUCT_NAME).observe(input_size)
    IN_PROGRESS.labels(PRODUCT_NAME).inc()
    started = time.perf_counter()

    try:
        if not resume or not resume.strip():
            raise ValueError("a synthetic or sanitized resume is required")
        if not job_description or not job_description.strip():
            raise ValueError("a job description is required")
        MODEL_CALLS.labels(PRODUCT_NAME, ACTIVE_MODEL).inc()
        messages = _messages(resume, job_description, focus)
        answer = _local_review(messages) if PRODUCT_MODE == "local" else _api_review(messages)
        if not answer:
            raise RuntimeError("empty model response")
        REQUESTS.labels(PRODUCT_NAME, "success").inc()
        OUTPUT_CHARACTERS.labels(PRODUCT_NAME).observe(len(answer))
        return answer
    except Exception as exc:  # The bounded category is exported; details stay in logs.
        category = _error_category(exc)
        ERRORS.labels(PRODUCT_NAME, category).inc()
        REQUESTS.labels(PRODUCT_NAME, "failure").inc()
        print(f"review failed category={category}: {exc}", flush=True)
        if category == "validation":
            return f"Please correct the input: {exc}."
        return f"The review could not be completed ({category}). Check the service logs."
    finally:
        REQUEST_DURATION.labels(PRODUCT_NAME).observe(time.perf_counter() - started)
        IN_PROGRESS.labels(PRODUCT_NAME).dec()


title_mode = "Hugging Face API" if PRODUCT_MODE == "api" else "Local CPU model"
with gr.Blocks(title=f"ResumeLens - {title_mode}") as demo:
    gr.Markdown(f"# ResumeLens AI - {title_mode}")
    gr.Markdown(
        "Compare a sanitized resume with a job description. "
        "Model output may be incorrect and must be reviewed by a person."
    )
    with gr.Row():
        resume_box = gr.Textbox(label="Sanitized resume", lines=18)
        job_box = gr.Textbox(label="Job description", lines=18)
    focus_box = gr.Dropdown(
        ["Balanced review", "Technical skills", "MLOps experience", "Writing clarity"],
        value="Balanced review",
        label="Review focus",
    )
    review_button = gr.Button("Review resume", variant="primary")
    output = gr.Markdown(label="Review")
    review_button.click(
        review_resume,
        inputs=[resume_box, job_box, focus_box],
        outputs=output,
        api_name="review",
    )


if __name__ == "__main__":
    start_http_server(8000)
    demo.queue(default_concurrency_limit=1, max_size=8).launch(
        server_name="0.0.0.0",
        server_port=7860,
        root_path=ROOT_PATH,
        show_error=False,
    )
