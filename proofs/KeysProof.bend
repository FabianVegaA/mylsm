import Base
import ../laws/Keys.bend as Laws
import ../src/Keys.bend as Keys

def Laws.cmp_refl_a():
  {==}

def Laws.cmp_order_ab():
  {==}

def Laws.key_cmp_refl(key):
  Keys.str_refl(key)

def Laws.key_cmp_eq_bridge(a, b):
  Keys.cmp_eq_bridge(a, b)

def Laws.key_cmp_trichotomy(a, b):
  Keys.cmp_one_hot_proof(Keys.cmp(a, b))
