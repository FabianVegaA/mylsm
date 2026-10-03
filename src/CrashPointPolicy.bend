import Base

# Pure checkpoint policy. An unset value is represented by the empty string;
# the non-empty guard distinguishes disabled injection from an exact match.
def nonempty(value: String) -> Bool:
  match value:
    case SNil{}: False{}
    case SCon{_, _}: True{}

def enabled(+configured: String, requested: String) -> Bool:
  Bool.and(nonempty(configured), String.eq(configured, requested))
