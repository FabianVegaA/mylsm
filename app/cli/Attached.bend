import Base

# Runs a child with inherited input and output, optional environment overrides, and optional log redirection.
def run(
  program: String,
  args: List<String>,
  env: List<(String & String)>,
  log_path: Maybe<&2, String>
) -> IO(Result<&1, &1, U32 & String, U32>):
  import "./attached_run.c"
  import "./attached_run.js"
