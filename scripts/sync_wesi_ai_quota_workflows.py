from pathlib import Path


def expr(secret: str) -> str:
    return "${{ secrets." + secret + " }}"


def insert_env_after(text: str, marker: str, pairs: list[tuple[str, str]]) -> str:
    lines = text.splitlines()
    if any(line.lstrip().startswith(pairs[0][0] + ":") for line in lines):
        return text
    for index, line in enumerate(lines):
        if line.lstrip().startswith(marker + ":"):
            indent = line[: len(line) - len(line.lstrip())]
            additions = [f"{indent}{name}: {expr(secret)}" for name, secret in pairs]
            lines[index + 1:index + 1] = additions
            return "\n".join(lines) + ("\n" if text.endswith("\n") else "")
    raise RuntimeError(f"env marker not found: {marker}")


PROJECT_ENV = [
    ("GEMINI_API_PROJECT", "GEMINI_API_PROJECT"),
    ("GEMINI_API_PROJECT_2", "GEMINI_API_PROJECT_2"),
    ("GEMINI_API_PROJECT_3", "GEMINI_API_PROJECT_3"),
    ("GEMINI_API_PROJECT_4", "GEMINI_API_PROJECT_4"),
    ("GEMINI_API_PROJECT_5", "GEMINI_API_PROJECT_5"),
]
SEALED_PROJECT_ENV = [
    ("GEMINI_PROJECT", "GEMINI_API_PROJECT"),
    ("GEMINI_PROJECT_2", "GEMINI_API_PROJECT_2"),
    ("GEMINI_PROJECT_3", "GEMINI_API_PROJECT_3"),
    ("GEMINI_PROJECT_4", "GEMINI_API_PROJECT_4"),
    ("GEMINI_PROJECT_5", "GEMINI_API_PROJECT_5"),
]
KEY_NAMES = "              'GEMINI_API_KEY_2','GEMINI_API_KEY_3','GEMINI_API_KEY_4','GEMINI_API_KEY_5',"
PROJECT_NAMES = "              'GEMINI_API_PROJECT','GEMINI_API_PROJECT_2','GEMINI_API_PROJECT_3','GEMINI_API_PROJECT_4','GEMINI_API_PROJECT_5',"
OLD_ALLOW = "GEMINI_API_KEY_2|GEMINI_API_KEY_3|GEMINI_API_KEY_4|GEMINI_API_KEY_5|GROQ_API_KEY|MISTRAL_API_KEY|OPENROUTER_API_KEY) ;;"
NEW_ALLOW = "GEMINI_API_KEY_2|GEMINI_API_KEY_3|GEMINI_API_KEY_4|GEMINI_API_KEY_5|GEMINI_API_PROJECT|GEMINI_API_PROJECT_2|GEMINI_API_PROJECT_3|GEMINI_API_PROJECT_4|GEMINI_API_PROJECT_5|GROQ_API_KEY|MISTRAL_API_KEY|OPENROUTER_API_KEY) ;;"


def patch_provider_bundle(text: str) -> str:
    if PROJECT_NAMES not in text:
        if KEY_NAMES not in text:
            raise RuntimeError("provider names marker not found")
        text = text.replace(KEY_NAMES, KEY_NAMES + "\n" + PROJECT_NAMES, 1)
    text = text.replace(OLD_ALLOW, NEW_ALLOW)
    return text


def patch_configure() -> None:
    path = Path(".github/workflows/configure-wesi-ai-router.yml")
    text = path.read_text(encoding="utf-8")
    text = insert_env_after(text, "GEMINI_API_KEY_5", PROJECT_ENV)
    text = patch_provider_bundle(text)
    path.write_text(text, encoding="utf-8")


def patch_deploy() -> None:
    path = Path(".github/workflows/deploy-wesi-ai.yml")
    text = path.read_text(encoding="utf-8")
    text = insert_env_after(text, "GEMINI_KEY_5", SEALED_PROJECT_ENV)
    # There is a second, separate provider-bundle env later in this workflow.
    text = insert_env_after(text, "GEMINI_API_KEY_5", PROJECT_ENV)

    loop = """          for index in range(2, 6):
              value = os.environ.get(f'GEMINI_KEY_{index}', '').strip()
              if value:
                  values[f'GEMINI_API_KEY_{index}_B64'] = value
"""
    loop_with_projects = """          primary_project = os.environ.get('GEMINI_PROJECT', '').strip()
          if primary_project:
              values['GEMINI_API_PROJECT_B64'] = primary_project
          for index in range(2, 6):
              value = os.environ.get(f'GEMINI_KEY_{index}', '').strip()
              if value:
                  values[f'GEMINI_API_KEY_{index}_B64'] = value
              project = os.environ.get(f'GEMINI_PROJECT_{index}', '').strip()
              if project:
                  values[f'GEMINI_API_PROJECT_{index}_B64'] = project
"""
    if "GEMINI_API_PROJECT_{index}_B64" not in text:
        if loop not in text:
            raise RuntimeError("sealed Gemini key loop not found")
        text = text.replace(loop, loop_with_projects, 1)

    text = patch_provider_bundle(text)
    path.write_text(text, encoding="utf-8")


def verify() -> None:
    configure = Path(".github/workflows/configure-wesi-ai-router.yml").read_text(encoding="utf-8")
    deploy = Path(".github/workflows/deploy-wesi-ai.yml").read_text(encoding="utf-8")
    required_configure = [
        "GEMINI_API_PROJECT_5: ${{ secrets.GEMINI_API_PROJECT_5 }}",
        "GEMINI_API_PROJECT_5|GROQ_API_KEY",
    ]
    required_deploy = [
        "GEMINI_PROJECT_5: ${{ secrets.GEMINI_API_PROJECT_5 }}",
        "GEMINI_API_PROJECT_5: ${{ secrets.GEMINI_API_PROJECT_5 }}",
        "values[f'GEMINI_API_PROJECT_{index}_B64'] = project",
        "GEMINI_API_PROJECT_5|GROQ_API_KEY",
    ]
    for marker in required_configure:
        if marker not in configure:
            raise RuntimeError(f"configure verification failed: {marker}")
    for marker in required_deploy:
        if marker not in deploy:
            raise RuntimeError(f"deploy verification failed: {marker}")


if __name__ == "__main__":
    patch_configure()
    patch_deploy()
    verify()
    print("Wesi AI Gemini project quota workflow support synchronized")
