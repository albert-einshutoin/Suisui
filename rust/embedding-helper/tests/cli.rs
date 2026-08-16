use std::{
    fs,
    path::{Path, PathBuf},
    process::{self, Command},
    sync::atomic::{AtomicU64, Ordering},
};

static SCRATCH_SEQUENCE: AtomicU64 = AtomicU64::new(0);

struct Scratch(PathBuf);

impl Scratch {
    fn new(label: &str) -> Self {
        let path = std::env::temp_dir().join(format!(
            "suisui-embedding-helper-cli-{label}-{}-{}",
            process::id(),
            SCRATCH_SEQUENCE.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir(&path).expect("scratch directory");
        Self(path)
    }

    fn path(&self) -> &Path {
        &self.0
    }
}

impl Drop for Scratch {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

fn model_dir(scratch: &Scratch) -> PathBuf {
    let model_dir = scratch.path().join("model");
    fs::create_dir(&model_dir).expect("model directory");
    for name in [
        "model.onnx",
        "tokenizer.json",
        "config.json",
        "special_tokens_map.json",
        "tokenizer_config.json",
    ] {
        fs::write(model_dir.join(name), "placeholder").expect("model file");
    }
    model_dir
}

fn run(model_dir: &Path, text_file: &Path, output: &Path) -> std::process::Output {
    Command::new(env!("CARGO_BIN_EXE_suisui-embedding-helper"))
        .args([
            "--model-dir",
            model_dir.to_str().expect("model path"),
            "--text-file",
            text_file.to_str().expect("text path"),
            "--output",
            output.to_str().expect("output path"),
        ])
        .output()
        .expect("helper launch")
}

#[test]
fn inference_failure_does_not_expose_text_contents() {
    let scratch = Scratch::new("secret");
    let model_dir = model_dir(&scratch);
    let text_file = scratch.path().join("private.txt");
    let secret = "do-not-log: private workspace note";
    fs::write(&text_file, secret).expect("text file");
    let output = scratch.path().join("output.json");

    let result = run(&model_dir, &text_file, &output);
    let transcript = format!(
        "{}{}",
        String::from_utf8_lossy(&result.stdout),
        String::from_utf8_lossy(&result.stderr)
    );

    assert!(!result.status.success());
    assert!(!transcript.contains(secret));
}

#[test]
fn oversized_text_is_rejected_without_exposure() {
    let scratch = Scratch::new("limit");
    let model_dir = model_dir(&scratch);
    let text_file = scratch.path().join("large.txt");
    let secret = "private-boundary-token";
    fs::write(&text_file, secret.repeat(4_000)).expect("text file");
    let output = scratch.path().join("output.json");

    let result = run(&model_dir, &text_file, &output);
    let transcript = format!(
        "{}{}",
        String::from_utf8_lossy(&result.stdout),
        String::from_utf8_lossy(&result.stderr)
    );

    assert!(!result.status.success());
    assert!(transcript.contains("input is too large"));
    assert!(!transcript.contains(secret));
}
