import Base

# Audited console and environment effects. C and JS twins share semantics and
# return empty strings for EOF and missing environment variables respectively.

# Read line for the console input and output.
def read_line() -> IO(Result<&1, &1, U32 & String, String>):
  import "./effs/read_line.c"
  import "./effs/read_line.js"

# Return env for the console input and output.
def get_env(name: String) -> IO(Result<&1, &1, U32 & String, String>):
  import "./effs/get_env.c"
  import "./effs/get_env.js"
