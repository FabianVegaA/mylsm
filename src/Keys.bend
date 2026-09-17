import Base

# Total-order comparison for keys. Base's String.cmp hands the strings back
# beside the verdict ((s1, s2), c); we take reusable copies and unpack via a
# helper (a match cannot scrutinize the computed call directly).
def unpack(p: (String & String) & Cmp) -> Cmp:
  match p:
    case ((_, _), c):
      c

def cmp(+a: String, +b: String) -> Cmp:
  unpack(String.cmp(a, b))
