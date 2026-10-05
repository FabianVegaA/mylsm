# Vendored from bend-collections 0x9ee2e9a299991dcc089fe22c7f3ceb5f
# (src/crypto/sha/core.bend), byte-identical except `Window` renamed to
# `ShaWindow`: Bend 2.0.28 Base added a GUI `Window` type that collides with
# this module's schedule-window type. Verify against NIST vectors, not the
# upstream PROOF.bend (which covers the original names).
import Base
import ./state.bend as S

# Represent ShaWindow data used by the SHA-256 compression implementation.
type ShaWindow is Data:
  W{a: U32, b: U32, c: U32, d: U32, e: U32, f: U32, g: U32, h: U32,
    i: U32, j: U32, k: U32, l: U32, m: U32, n: U32, o: U32, p: U32}

# SHA-256 for byte sequences. Each input U32 contributes its low 8 bits.
# SHA-256 arithmetic is native U32, hence addition wraps modulo 2^32.
def initial() -> S.State:
  S.H{1779033703, 3144134277, 1013904242, 2773480762,
    1359893119, 2600822924, 528734635, 1541459225}

# Handle rotr in the SHA-256 compression implementation.
def rotr(+word: U32, +bit_shift: Nat) -> U32:
  (U32.shrn(word, bit_shift) .|. U32.shln(word, Nat.sub(32n, bit_shift)) : U32)

# Compute the big sigma function for 0 for the SHA-256 compression implementation.
def big0(+word: U32) -> U32:
  ((U32.shrn(word, 2n) .|. U32.shln(word, 30n))
    .^. (U32.shrn(word, 13n) .|. U32.shln(word, 19n))
    .^. (U32.shrn(word, 22n) .|. U32.shln(word, 10n)) : U32)

# Compute the big sigma function for 1 for the SHA-256 compression implementation.
def big1(+word: U32) -> U32:
  ((U32.shrn(word, 6n) .|. U32.shln(word, 26n))
    .^. (U32.shrn(word, 11n) .|. U32.shln(word, 21n))
    .^. (U32.shrn(word, 25n) .|. U32.shln(word, 7n)) : U32)

# Compute the small sigma function for 0 for the SHA-256 compression implementation.
def small0(+word: U32) -> U32:
  ((U32.shrn(word, 7n) .|. U32.shln(word, 25n))
    .^. (U32.shrn(word, 18n) .|. U32.shln(word, 14n))
    .^. U32.shrn(word, 3n) : U32)

# Compute the small sigma function for 1 for the SHA-256 compression implementation.
def small1(+word: U32) -> U32:
  ((U32.shrn(word, 17n) .|. U32.shln(word, 15n))
    .^. (U32.shrn(word, 19n) .|. U32.shln(word, 13n))
    .^. U32.shrn(word, 10n) : U32)

# Handle choose in the SHA-256 compression implementation.
def choose(+word_x: U32, word_y: U32, word_z: U32) -> U32:
  ((word_x .&. word_y) .^. (U32.not(word_x) .&. word_z) : U32)

# Handle majority in the SHA-256 compression implementation.
def majority(+word_x: U32, +word_y: U32, +word_z: U32) -> U32:
  ((word_x .&. word_y) .^. (word_x .&. word_z) .^. (word_y .&. word_z) : U32)

# Handle step in the SHA-256 compression implementation.
def step(state: S.State, round_constant: U32, schedule_word: U32) -> S.State:
  S.H{+a, +b, +c, d, +e, +f, +g, h} = state
  +t1 = (h + big1(e) + choose(e, f, g) + round_constant + schedule_word : U32)
  t2 = (big0(a) + majority(a, b, c) : U32)
  S.H{(t1 + t2 : U32), a, b, c, (d + t1 : U32), e, f, g}

# Feed forward for the SHA-256 compression implementation.
def feedforward(prior_state: S.State, round_state: S.State) -> S.State:
  S.H{a, b, c, d, e, f, g, h} = prior_state
  S.H{i, j, k, l, m, n, o, p} = round_state
  S.H{(a + i : U32), (b + j : U32), (c + k : U32), (d + l : U32),
    (e + m : U32), (f + n : U32), (g + o : U32), (h + p : U32)}

# Handle get in the SHA-256 compression implementation.
def get(xs: List<&2, U32>, index: Nat) -> U32:
  match xs index:
    case Nil{} _:
      0
    case h <> t 0n:
      h
    case h <> t 1n+p:
      get(t, p)

# Reverse history: at round t, index j contains W[t-1-j].
def next_word_slow(+history: List<&2, U32>) -> U32:
  (small1(get(history, 1n)) + get(history, 6n)
    + small0(get(history, 14n)) + get(history, 15n) : U32)

# Schedule histories always contain at least 16 words. Destructuring that prefix
# avoids four independent linked-list walks for every expanded word; the fallback
# preserves the total behavior used by the universal refinement theorem.
def next_word(+history: List<&2, U32>) -> U32:
  match history:
    case a <> b <> c <> d <> e <> f <> g <> h <> i <> j <> k <> l <> m <> n <> o <> (p <> rest):
      (small1(b) + g + small0(o) + p : U32)
    case _:
      next_word_slow(history)

# Handle expand in the SHA-256 compression implementation.
def expand(rounds_left: Nat, +history: List<&2, U32>) -> List<&2, U32>:
  match rounds_left:
    case 0n:
      Nil{}
    case 1n+p:
      +w = next_word(history)
      w <> expand(p, w <> history)

# Handle schedule in the SHA-256 compression implementation.
def schedule(extra: Nat, +block: List<&2, U32>) -> List<&2, U32>:
  List.append(&2, U32, block,
    expand(extra, List.reverse(&2, U32, block)))

# Handle rounds in the SHA-256 compression implementation.
def rounds(ks: List<&2, U32>, ws: List<&2, U32>, state: S.State) -> S.State:
  match ks ws:
    case Nil{} _:
      state
    case k <> kt Nil{}:
      state
    case k <> kt w <> wt:
      rounds(kt, wt, step(state, k, w))

# Compression consumes an already expanded 64-word schedule.
def compress(ws: List<&2, U32>, ks: List<&2, U32>, +state: S.State) -> S.State:
  feedforward(state, rounds(ks, ws, state))

# Generate each derived schedule word immediately before its round. The reverse
# history is still retained for the recurrence, but the chronological 48-word
# extension is never materialized.
def expanded_rounds(rounds_left: Nat, +history: List<&2, U32>, ks: List<&2, U32>, state: S.State) -> S.State:
  match rounds_left ks:
    case 0n _:
      state
    case 1n+p Nil{}:
      state
    case 1n+p k <> kt:
      +w = next_word(history)
      expanded_rounds(p, w <> history, kt, step(state, k, w))

# Consume the original block words, then continue directly with its expansion.
def schedule_rounds(
  ws: List<&2, U32>,
  +extra: Nat,
  +history: List<&2, U32>,
  ks: List<&2, U32>,
  state: S.State
) -> S.State:
  match ws ks:
    case Nil{} _:
      expanded_rounds(extra, history, ks, state)
    case w <> wt Nil{}:
      state
    case w <> wt k <> kt:
      schedule_rounds(wt, extra, history, kt, step(state, k, w))

# A fixed rolling window drops schedule words as soon as they are older than 16
# rounds. This avoids growing and reference-counting the reverse history list.
def window_rounds(rounds_left: Nat, win: ShaWindow, ks: List<&2, U32>, state: S.State) -> S.State:
  match rounds_left win ks:
    case 0n _ _:
      state
    case 1n+q _ Nil{}:
      state
    case 1n+q W{a, +b, c, d, e, f, +g, h, i, j, l, m, o, r, +t, +u} k <> kt:
      +w = (small1(b) + g + small0(t) + u : U32)
      window_rounds(q, W{w, a, b, c, d, e, f, g, h, i, j, l, m, o, r, t}, kt,
        step(state, k, w))

# Handle window schedule rounds in the SHA-256 compression implementation.
def window_schedule_rounds(
  ws: List<&2, U32>,
  +extra: Nat,
  win: ShaWindow,
  ks: List<&2, U32>,
  state: S.State
) -> S.State:
  match ws ks:
    case Nil{} _:
      window_rounds(extra, win, ks, state)
    case w <> wt Nil{}:
      state
    case w <> wt k <> kt:
      window_schedule_rounds(wt, extra, win, kt, step(state, k, w))

# Handle fused compress slow in the SHA-256 compression implementation.
def fused_compress_slow(+block: List<&2, U32>, +extra: Nat, +ks: List<&2, U32>, +state: S.State) -> S.State:
  feedforward(state, schedule_rounds(block, extra, List.reverse(&2, U32, block), ks, state))

# Handle fused compress in the SHA-256 compression implementation.
def fused_compress(+block: List<&2, U32>, +extra: Nat, +ks: List<&2, U32>, +state: S.State) -> S.State:
  match block:
    case a <> b <> c <> d <> e <> f <> g <> h <> i <> j <> k <> l <> m <> n <> o <> p <> Nil{}:
      feedforward(state, window_schedule_rounds(
        [a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p], extra,
        W{p, o, n, m, l, k, j, i, h, g, f, e, d, c, b, a}, ks, state))
    case _:
      fused_compress_slow(block, extra, ks, state)

# Fast path for the 16-word blocks produced by block_bytes. It executes the
# seed rounds directly and constructs only the fixed rolling window.
def window_compress16(
  +word_a: U32,
  +word_b: U32,
  +word_c: U32,
  +word_d: U32,
  +word_e: U32,
  +word_f: U32,
  +word_g: U32,
  +word_h: U32,
  +word_i: U32,
  +word_j: U32,
  +round_constant: U32,
  +word_l: U32,
  +word_m: U32,
  +count: U32,
  +word_o: U32,
  +word_p: U32,
  +extra: Nat,
  +ks: List<&2, U32>,
  +state: S.State
) -> S.State:
  match ks:
    case k0 <> k1 <> k2 <> k3 <> k4 <> k5 <> k6 <> k7 <>
      k8 <> k9 <> k10 <> k11 <> k12 <> k13 <> k14 <> k15 <> kt:
      s1 = step(state, k0, word_a)
      s2 = step(s1, k1, word_b)
      s3 = step(s2, k2, word_c)
      s4 = step(s3, k3, word_d)
      s5 = step(s4, k4, word_e)
      s6 = step(s5, k5, word_f)
      s7 = step(s6, k6, word_g)
      s8 = step(s7, k7, word_h)
      s9 = step(s8, k8, word_i)
      s10 = step(s9, k9, word_j)
      s11 = step(s10, k10, round_constant)
      s12 = step(s11, k11, word_l)
      s13 = step(s12, k12, word_m)
      s14 = step(s13, k13, count)
      s15 = step(s14, k14, word_o)
      s16 = step(s15, k15, word_p)
      feedforward(state, window_rounds(extra,
        W{word_p, word_o, count, word_m, word_l, round_constant, word_j, word_i, word_h, word_g, word_f, word_e, word_d, word_c, word_b, word_a}, kt, s16))
    case _:
      fused_compress([word_a, word_b, word_c, word_d, word_e, word_f, word_g, word_h, word_i, word_j, round_constant, word_l, word_m, count, word_o, word_p], extra, ks, state)

# Handle be32 in the SHA-256 compression implementation.
def be32(+word: U32) -> List<&2, U32>:
  [U32.shrn(word, 24n), (U32.shrn(word, 16n) .&. 255 : U32),
   (U32.shrn(word, 8n) .&. 255 : U32), (word .&. 255 : U32)]

# Return the length of gth octets in the SHA-256 compression implementation.
def length_octets(count: Nat, +byte_length: Nat, acc: List<&2, U32>) -> List<&2, U32>:
  match count:
    case 0n:
      acc
    case 1n+p:
      length_octets(p, Nat.div(byte_length, 256n), U32.from_nat(Nat.mod(byte_length, 256n)) <> acc)

# Handle bit length in the SHA-256 compression implementation.
def bit_length(+byte_length: Nat) -> List<&2, U32>:
  length_octets(7n, Nat.div(byte_length, 32n),
    [U32.shln(U32.from_nat(Nat.mod(byte_length, 32n)), 3n)])

# Handle pack in the SHA-256 compression implementation.
def pack(word_a: U32, word_b: U32, word_c: U32, word_d: U32) -> U32:
  (U32.shln((word_a .&. 255 : U32), 24n)
    .|. U32.shln((word_b .&. 255 : U32), 16n)
    .|. U32.shln((word_c .&. 255 : U32), 8n) .|. (word_d .&. 255) : U32)

# Handle digest in the SHA-256 compression implementation.
def digest(state: S.State) -> List<&2, U32>:
  S.H{a, b, c, d, e, f, g, h} = state
  [a, b, c, d, e, f, g, h]

# Generic block decoder over a padded byte list and any constant table. The
# fast path below is proved equal to it with the FIPS table.
def block_bytes(bytes: List<&2, U32>, +extra: Nat, +ks: List<&2, U32>, state: S.State) -> S.State:
  match bytes:
    case b0 <> b1 <> b2 <> b3 <> b4 <> b5 <> b6 <> b7 <> b8 <> b9 <> b10 <> b11 <> b12 <> b13 <> b14 <> b15 <> b16 <> b17 <> b18 <> b19 <> b20 <> b21 <> b22 <> b23 <> b24 <> b25 <> b26 <> b27 <> b28 <> b29 <> b30 <> b31 <> b32 <> b33 <> b34 <> b35 <> b36 <> b37 <> b38 <> b39 <> b40 <> b41 <> b42 <> b43 <> b44 <> b45 <> b46 <> b47 <> b48 <> b49 <> b50 <> b51 <> b52 <> b53 <> b54 <> b55 <> b56 <> b57 <> b58 <> b59 <> b60 <> b61 <> b62 <> b63 <> rest:
      block_bytes(rest, extra, ks, window_compress16(
        pack(b0, b1, b2, b3), pack(b4, b5, b6, b7), pack(b8, b9, b10, b11), pack(b12, b13, b14, b15),
        pack(b16, b17, b18, b19), pack(b20, b21, b22, b23), pack(b24, b25, b26, b27), pack(b28, b29, b30, b31),
        pack(b32, b33, b34, b35), pack(b36, b37, b38, b39), pack(b40, b41, b42, b43), pack(b44, b45, b46, b47),
        pack(b48, b49, b50, b51), pack(b52, b53, b54, b55), pack(b56, b57, b58, b59), pack(b60, b61, b62, b63),
        extra, ks, state))
    case _:
      state

# FIPS 180-4 round constants, the table the specialized rounds below inline.
def round_constants() -> List<&2, U32>:
  [1116352408, 1899447441, 3049323471, 3921009573,
   961987163, 1508970993, 2453635748, 2870763221,
   3624381080, 310598401, 607225278, 1426881987,
   1925078388, 2162078206, 2614888103, 3248222580,
   3835390401, 4022224774, 264347078, 604807628,
   770255983, 1249150122, 1555081692, 1996064986,
   2554220882, 2821834349, 2952996808, 3210313671,
   3336571891, 3584528711, 113926993, 338241895,
   666307205, 773529912, 1294757372, 1396182291,
   1695183700, 1986661051, 2177026350, 2456956037,
   2730485921, 2820302411, 3259730800, 3345764771,
   3516065817, 3600352804, 4094571909, 275423344,
   430227734, 506948616, 659060556, 883997877,
   958139571, 1322822218, 1537002063, 1747873779,
   1955562222, 2024104815, 2227730452, 2361852424,
   2428436474, 2756734187, 3204031479, 3329325298]

# SHA-256 round t (16 <= t < 64) with its constant as a literal. Like
# window_rounds, q bounds the remaining rounds (48 for SHA-256) and each round
# derives its schedule word from the rolling window before continuing with
# round t+1. Defined last-to-first because names must precede use.
def kr64(state: S.State) -> S.State:
  state

# Return the SHA-256 round constant for schedule index 63.
def kr63(rounds_left: Nat, win: ShaWindow, state: S.State) -> S.State:
  match rounds_left win:
    case 0n _:
      state
    case 1n+z W{a, +b, c, d, e, f, +g, h, i, j, l, m, o, r, +t, +u}:
      +w = (small1(b) + g + small0(t) + u : U32)
      kr64(step(state, 3329325298, w))

# Return the SHA-256 round constant for schedule index 62.
def kr62(rounds_left: Nat, win: ShaWindow, state: S.State) -> S.State:
  match rounds_left win:
    case 0n _:
      state
    case 1n+z W{a, +b, c, d, e, f, +g, h, i, j, l, m, o, r, +t, +u}:
      +w = (small1(b) + g + small0(t) + u : U32)
      kr63(z, W{w, a, b, c, d, e, f, g, h, i, j, l, m, o, r, t}, step(state, 3204031479, w))

# Return the SHA-256 round constant for schedule index 61.
def kr61(rounds_left: Nat, win: ShaWindow, state: S.State) -> S.State:
  match rounds_left win:
    case 0n _:
      state
    case 1n+z W{a, +b, c, d, e, f, +g, h, i, j, l, m, o, r, +t, +u}:
      +w = (small1(b) + g + small0(t) + u : U32)
      kr62(z, W{w, a, b, c, d, e, f, g, h, i, j, l, m, o, r, t}, step(state, 2756734187, w))

# Return the SHA-256 round constant for schedule index 60.
def kr60(rounds_left: Nat, win: ShaWindow, state: S.State) -> S.State:
  match rounds_left win:
    case 0n _:
      state
    case 1n+z W{a, +b, c, d, e, f, +g, h, i, j, l, m, o, r, +t, +u}:
      +w = (small1(b) + g + small0(t) + u : U32)
      kr61(z, W{w, a, b, c, d, e, f, g, h, i, j, l, m, o, r, t}, step(state, 2428436474, w))

# Return the SHA-256 round constant for schedule index 59.
def kr59(rounds_left: Nat, win: ShaWindow, state: S.State) -> S.State:
  match rounds_left win:
    case 0n _:
      state
    case 1n+z W{a, +b, c, d, e, f, +g, h, i, j, l, m, o, r, +t, +u}:
      +w = (small1(b) + g + small0(t) + u : U32)
      kr60(z, W{w, a, b, c, d, e, f, g, h, i, j, l, m, o, r, t}, step(state, 2361852424, w))

# Return the SHA-256 round constant for schedule index 58.
def kr58(rounds_left: Nat, win: ShaWindow, state: S.State) -> S.State:
  match rounds_left win:
    case 0n _:
      state
    case 1n+z W{a, +b, c, d, e, f, +g, h, i, j, l, m, o, r, +t, +u}:
      +w = (small1(b) + g + small0(t) + u : U32)
      kr59(z, W{w, a, b, c, d, e, f, g, h, i, j, l, m, o, r, t}, step(state, 2227730452, w))

# Return the SHA-256 round constant for schedule index 57.
def kr57(rounds_left: Nat, win: ShaWindow, state: S.State) -> S.State:
  match rounds_left win:
    case 0n _:
      state
    case 1n+z W{a, +b, c, d, e, f, +g, h, i, j, l, m, o, r, +t, +u}:
      +w = (small1(b) + g + small0(t) + u : U32)
      kr58(z, W{w, a, b, c, d, e, f, g, h, i, j, l, m, o, r, t}, step(state, 2024104815, w))

# Return the SHA-256 round constant for schedule index 56.
def kr56(rounds_left: Nat, win: ShaWindow, state: S.State) -> S.State:
  match rounds_left win:
    case 0n _:
      state
    case 1n+z W{a, +b, c, d, e, f, +g, h, i, j, l, m, o, r, +t, +u}:
      +w = (small1(b) + g + small0(t) + u : U32)
      kr57(z, W{w, a, b, c, d, e, f, g, h, i, j, l, m, o, r, t}, step(state, 1955562222, w))

# Return the SHA-256 round constant for schedule index 55.
def kr55(rounds_left: Nat, win: ShaWindow, state: S.State) -> S.State:
  match rounds_left win:
    case 0n _:
      state
    case 1n+z W{a, +b, c, d, e, f, +g, h, i, j, l, m, o, r, +t, +u}:
      +w = (small1(b) + g + small0(t) + u : U32)
      kr56(z, W{w, a, b, c, d, e, f, g, h, i, j, l, m, o, r, t}, step(state, 1747873779, w))

# Return the SHA-256 round constant for schedule index 54.
def kr54(rounds_left: Nat, win: ShaWindow, state: S.State) -> S.State:
  match rounds_left win:
    case 0n _:
      state
    case 1n+z W{a, +b, c, d, e, f, +g, h, i, j, l, m, o, r, +t, +u}:
      +w = (small1(b) + g + small0(t) + u : U32)
      kr55(z, W{w, a, b, c, d, e, f, g, h, i, j, l, m, o, r, t}, step(state, 1537002063, w))

# Return the SHA-256 round constant for schedule index 53.
def kr53(rounds_left: Nat, win: ShaWindow, state: S.State) -> S.State:
  match rounds_left win:
    case 0n _:
      state
    case 1n+z W{a, +b, c, d, e, f, +g, h, i, j, l, m, o, r, +t, +u}:
      +w = (small1(b) + g + small0(t) + u : U32)
      kr54(z, W{w, a, b, c, d, e, f, g, h, i, j, l, m, o, r, t}, step(state, 1322822218, w))

# Return the SHA-256 round constant for schedule index 52.
def kr52(rounds_left: Nat, win: ShaWindow, state: S.State) -> S.State:
  match rounds_left win:
    case 0n _:
      state
    case 1n+z W{a, +b, c, d, e, f, +g, h, i, j, l, m, o, r, +t, +u}:
      +w = (small1(b) + g + small0(t) + u : U32)
      kr53(z, W{w, a, b, c, d, e, f, g, h, i, j, l, m, o, r, t}, step(state, 958139571, w))

# Return the SHA-256 round constant for schedule index 51.
def kr51(rounds_left: Nat, win: ShaWindow, state: S.State) -> S.State:
  match rounds_left win:
    case 0n _:
      state
    case 1n+z W{a, +b, c, d, e, f, +g, h, i, j, l, m, o, r, +t, +u}:
      +w = (small1(b) + g + small0(t) + u : U32)
      kr52(z, W{w, a, b, c, d, e, f, g, h, i, j, l, m, o, r, t}, step(state, 883997877, w))

# Return the SHA-256 round constant for schedule index 50.
def kr50(rounds_left: Nat, win: ShaWindow, state: S.State) -> S.State:
  match rounds_left win:
    case 0n _:
      state
    case 1n+z W{a, +b, c, d, e, f, +g, h, i, j, l, m, o, r, +t, +u}:
      +w = (small1(b) + g + small0(t) + u : U32)
      kr51(z, W{w, a, b, c, d, e, f, g, h, i, j, l, m, o, r, t}, step(state, 659060556, w))

# Return the SHA-256 round constant for schedule index 49.
def kr49(rounds_left: Nat, win: ShaWindow, state: S.State) -> S.State:
  match rounds_left win:
    case 0n _:
      state
    case 1n+z W{a, +b, c, d, e, f, +g, h, i, j, l, m, o, r, +t, +u}:
      +w = (small1(b) + g + small0(t) + u : U32)
      kr50(z, W{w, a, b, c, d, e, f, g, h, i, j, l, m, o, r, t}, step(state, 506948616, w))

# Return the SHA-256 round constant for schedule index 48.
def kr48(rounds_left: Nat, win: ShaWindow, state: S.State) -> S.State:
  match rounds_left win:
    case 0n _:
      state
    case 1n+z W{a, +b, c, d, e, f, +g, h, i, j, l, m, o, r, +t, +u}:
      +w = (small1(b) + g + small0(t) + u : U32)
      kr49(z, W{w, a, b, c, d, e, f, g, h, i, j, l, m, o, r, t}, step(state, 430227734, w))

# Return the SHA-256 round constant for schedule index 47.
def kr47(rounds_left: Nat, win: ShaWindow, state: S.State) -> S.State:
  match rounds_left win:
    case 0n _:
      state
    case 1n+z W{a, +b, c, d, e, f, +g, h, i, j, l, m, o, r, +t, +u}:
      +w = (small1(b) + g + small0(t) + u : U32)
      kr48(z, W{w, a, b, c, d, e, f, g, h, i, j, l, m, o, r, t}, step(state, 275423344, w))

# Return the SHA-256 round constant for schedule index 46.
def kr46(rounds_left: Nat, win: ShaWindow, state: S.State) -> S.State:
  match rounds_left win:
    case 0n _:
      state
    case 1n+z W{a, +b, c, d, e, f, +g, h, i, j, l, m, o, r, +t, +u}:
      +w = (small1(b) + g + small0(t) + u : U32)
      kr47(z, W{w, a, b, c, d, e, f, g, h, i, j, l, m, o, r, t}, step(state, 4094571909, w))

# Return the SHA-256 round constant for schedule index 45.
def kr45(rounds_left: Nat, win: ShaWindow, state: S.State) -> S.State:
  match rounds_left win:
    case 0n _:
      state
    case 1n+z W{a, +b, c, d, e, f, +g, h, i, j, l, m, o, r, +t, +u}:
      +w = (small1(b) + g + small0(t) + u : U32)
      kr46(z, W{w, a, b, c, d, e, f, g, h, i, j, l, m, o, r, t}, step(state, 3600352804, w))

# Return the SHA-256 round constant for schedule index 44.
def kr44(rounds_left: Nat, win: ShaWindow, state: S.State) -> S.State:
  match rounds_left win:
    case 0n _:
      state
    case 1n+z W{a, +b, c, d, e, f, +g, h, i, j, l, m, o, r, +t, +u}:
      +w = (small1(b) + g + small0(t) + u : U32)
      kr45(z, W{w, a, b, c, d, e, f, g, h, i, j, l, m, o, r, t}, step(state, 3516065817, w))

# Return the SHA-256 round constant for schedule index 43.
def kr43(rounds_left: Nat, win: ShaWindow, state: S.State) -> S.State:
  match rounds_left win:
    case 0n _:
      state
    case 1n+z W{a, +b, c, d, e, f, +g, h, i, j, l, m, o, r, +t, +u}:
      +w = (small1(b) + g + small0(t) + u : U32)
      kr44(z, W{w, a, b, c, d, e, f, g, h, i, j, l, m, o, r, t}, step(state, 3345764771, w))

# Return the SHA-256 round constant for schedule index 42.
def kr42(rounds_left: Nat, win: ShaWindow, state: S.State) -> S.State:
  match rounds_left win:
    case 0n _:
      state
    case 1n+z W{a, +b, c, d, e, f, +g, h, i, j, l, m, o, r, +t, +u}:
      +w = (small1(b) + g + small0(t) + u : U32)
      kr43(z, W{w, a, b, c, d, e, f, g, h, i, j, l, m, o, r, t}, step(state, 3259730800, w))

# Return the SHA-256 round constant for schedule index 41.
def kr41(rounds_left: Nat, win: ShaWindow, state: S.State) -> S.State:
  match rounds_left win:
    case 0n _:
      state
    case 1n+z W{a, +b, c, d, e, f, +g, h, i, j, l, m, o, r, +t, +u}:
      +w = (small1(b) + g + small0(t) + u : U32)
      kr42(z, W{w, a, b, c, d, e, f, g, h, i, j, l, m, o, r, t}, step(state, 2820302411, w))

# Return the SHA-256 round constant for schedule index 40.
def kr40(rounds_left: Nat, win: ShaWindow, state: S.State) -> S.State:
  match rounds_left win:
    case 0n _:
      state
    case 1n+z W{a, +b, c, d, e, f, +g, h, i, j, l, m, o, r, +t, +u}:
      +w = (small1(b) + g + small0(t) + u : U32)
      kr41(z, W{w, a, b, c, d, e, f, g, h, i, j, l, m, o, r, t}, step(state, 2730485921, w))

# Return the SHA-256 round constant for schedule index 39.
def kr39(rounds_left: Nat, win: ShaWindow, state: S.State) -> S.State:
  match rounds_left win:
    case 0n _:
      state
    case 1n+z W{a, +b, c, d, e, f, +g, h, i, j, l, m, o, r, +t, +u}:
      +w = (small1(b) + g + small0(t) + u : U32)
      kr40(z, W{w, a, b, c, d, e, f, g, h, i, j, l, m, o, r, t}, step(state, 2456956037, w))

# Return the SHA-256 round constant for schedule index 38.
def kr38(rounds_left: Nat, win: ShaWindow, state: S.State) -> S.State:
  match rounds_left win:
    case 0n _:
      state
    case 1n+z W{a, +b, c, d, e, f, +g, h, i, j, l, m, o, r, +t, +u}:
      +w = (small1(b) + g + small0(t) + u : U32)
      kr39(z, W{w, a, b, c, d, e, f, g, h, i, j, l, m, o, r, t}, step(state, 2177026350, w))

# Return the SHA-256 round constant for schedule index 37.
def kr37(rounds_left: Nat, win: ShaWindow, state: S.State) -> S.State:
  match rounds_left win:
    case 0n _:
      state
    case 1n+z W{a, +b, c, d, e, f, +g, h, i, j, l, m, o, r, +t, +u}:
      +w = (small1(b) + g + small0(t) + u : U32)
      kr38(z, W{w, a, b, c, d, e, f, g, h, i, j, l, m, o, r, t}, step(state, 1986661051, w))

# Return the SHA-256 round constant for schedule index 36.
def kr36(rounds_left: Nat, win: ShaWindow, state: S.State) -> S.State:
  match rounds_left win:
    case 0n _:
      state
    case 1n+z W{a, +b, c, d, e, f, +g, h, i, j, l, m, o, r, +t, +u}:
      +w = (small1(b) + g + small0(t) + u : U32)
      kr37(z, W{w, a, b, c, d, e, f, g, h, i, j, l, m, o, r, t}, step(state, 1695183700, w))

# Return the SHA-256 round constant for schedule index 35.
def kr35(rounds_left: Nat, win: ShaWindow, state: S.State) -> S.State:
  match rounds_left win:
    case 0n _:
      state
    case 1n+z W{a, +b, c, d, e, f, +g, h, i, j, l, m, o, r, +t, +u}:
      +w = (small1(b) + g + small0(t) + u : U32)
      kr36(z, W{w, a, b, c, d, e, f, g, h, i, j, l, m, o, r, t}, step(state, 1396182291, w))

# Return the SHA-256 round constant for schedule index 34.
def kr34(rounds_left: Nat, win: ShaWindow, state: S.State) -> S.State:
  match rounds_left win:
    case 0n _:
      state
    case 1n+z W{a, +b, c, d, e, f, +g, h, i, j, l, m, o, r, +t, +u}:
      +w = (small1(b) + g + small0(t) + u : U32)
      kr35(z, W{w, a, b, c, d, e, f, g, h, i, j, l, m, o, r, t}, step(state, 1294757372, w))

# Return the SHA-256 round constant for schedule index 33.
def kr33(rounds_left: Nat, win: ShaWindow, state: S.State) -> S.State:
  match rounds_left win:
    case 0n _:
      state
    case 1n+z W{a, +b, c, d, e, f, +g, h, i, j, l, m, o, r, +t, +u}:
      +w = (small1(b) + g + small0(t) + u : U32)
      kr34(z, W{w, a, b, c, d, e, f, g, h, i, j, l, m, o, r, t}, step(state, 773529912, w))

# Return the SHA-256 round constant for schedule index 32.
def kr32(rounds_left: Nat, win: ShaWindow, state: S.State) -> S.State:
  match rounds_left win:
    case 0n _:
      state
    case 1n+z W{a, +b, c, d, e, f, +g, h, i, j, l, m, o, r, +t, +u}:
      +w = (small1(b) + g + small0(t) + u : U32)
      kr33(z, W{w, a, b, c, d, e, f, g, h, i, j, l, m, o, r, t}, step(state, 666307205, w))

# Return the SHA-256 round constant for schedule index 31.
def kr31(rounds_left: Nat, win: ShaWindow, state: S.State) -> S.State:
  match rounds_left win:
    case 0n _:
      state
    case 1n+z W{a, +b, c, d, e, f, +g, h, i, j, l, m, o, r, +t, +u}:
      +w = (small1(b) + g + small0(t) + u : U32)
      kr32(z, W{w, a, b, c, d, e, f, g, h, i, j, l, m, o, r, t}, step(state, 338241895, w))

# Return the SHA-256 round constant for schedule index 30.
def kr30(rounds_left: Nat, win: ShaWindow, state: S.State) -> S.State:
  match rounds_left win:
    case 0n _:
      state
    case 1n+z W{a, +b, c, d, e, f, +g, h, i, j, l, m, o, r, +t, +u}:
      +w = (small1(b) + g + small0(t) + u : U32)
      kr31(z, W{w, a, b, c, d, e, f, g, h, i, j, l, m, o, r, t}, step(state, 113926993, w))

# Return the SHA-256 round constant for schedule index 29.
def kr29(rounds_left: Nat, win: ShaWindow, state: S.State) -> S.State:
  match rounds_left win:
    case 0n _:
      state
    case 1n+z W{a, +b, c, d, e, f, +g, h, i, j, l, m, o, r, +t, +u}:
      +w = (small1(b) + g + small0(t) + u : U32)
      kr30(z, W{w, a, b, c, d, e, f, g, h, i, j, l, m, o, r, t}, step(state, 3584528711, w))

# Return the SHA-256 round constant for schedule index 28.
def kr28(rounds_left: Nat, win: ShaWindow, state: S.State) -> S.State:
  match rounds_left win:
    case 0n _:
      state
    case 1n+z W{a, +b, c, d, e, f, +g, h, i, j, l, m, o, r, +t, +u}:
      +w = (small1(b) + g + small0(t) + u : U32)
      kr29(z, W{w, a, b, c, d, e, f, g, h, i, j, l, m, o, r, t}, step(state, 3336571891, w))

# Return the SHA-256 round constant for schedule index 27.
def kr27(rounds_left: Nat, win: ShaWindow, state: S.State) -> S.State:
  match rounds_left win:
    case 0n _:
      state
    case 1n+z W{a, +b, c, d, e, f, +g, h, i, j, l, m, o, r, +t, +u}:
      +w = (small1(b) + g + small0(t) + u : U32)
      kr28(z, W{w, a, b, c, d, e, f, g, h, i, j, l, m, o, r, t}, step(state, 3210313671, w))

# Return the SHA-256 round constant for schedule index 26.
def kr26(rounds_left: Nat, win: ShaWindow, state: S.State) -> S.State:
  match rounds_left win:
    case 0n _:
      state
    case 1n+z W{a, +b, c, d, e, f, +g, h, i, j, l, m, o, r, +t, +u}:
      +w = (small1(b) + g + small0(t) + u : U32)
      kr27(z, W{w, a, b, c, d, e, f, g, h, i, j, l, m, o, r, t}, step(state, 2952996808, w))

# Return the SHA-256 round constant for schedule index 25.
def kr25(rounds_left: Nat, win: ShaWindow, state: S.State) -> S.State:
  match rounds_left win:
    case 0n _:
      state
    case 1n+z W{a, +b, c, d, e, f, +g, h, i, j, l, m, o, r, +t, +u}:
      +w = (small1(b) + g + small0(t) + u : U32)
      kr26(z, W{w, a, b, c, d, e, f, g, h, i, j, l, m, o, r, t}, step(state, 2821834349, w))

# Return the SHA-256 round constant for schedule index 24.
def kr24(rounds_left: Nat, win: ShaWindow, state: S.State) -> S.State:
  match rounds_left win:
    case 0n _:
      state
    case 1n+z W{a, +b, c, d, e, f, +g, h, i, j, l, m, o, r, +t, +u}:
      +w = (small1(b) + g + small0(t) + u : U32)
      kr25(z, W{w, a, b, c, d, e, f, g, h, i, j, l, m, o, r, t}, step(state, 2554220882, w))

# Return the SHA-256 round constant for schedule index 23.
def kr23(rounds_left: Nat, win: ShaWindow, state: S.State) -> S.State:
  match rounds_left win:
    case 0n _:
      state
    case 1n+z W{a, +b, c, d, e, f, +g, h, i, j, l, m, o, r, +t, +u}:
      +w = (small1(b) + g + small0(t) + u : U32)
      kr24(z, W{w, a, b, c, d, e, f, g, h, i, j, l, m, o, r, t}, step(state, 1996064986, w))

# Return the SHA-256 round constant for schedule index 22.
def kr22(rounds_left: Nat, win: ShaWindow, state: S.State) -> S.State:
  match rounds_left win:
    case 0n _:
      state
    case 1n+z W{a, +b, c, d, e, f, +g, h, i, j, l, m, o, r, +t, +u}:
      +w = (small1(b) + g + small0(t) + u : U32)
      kr23(z, W{w, a, b, c, d, e, f, g, h, i, j, l, m, o, r, t}, step(state, 1555081692, w))

# Return the SHA-256 round constant for schedule index 21.
def kr21(rounds_left: Nat, win: ShaWindow, state: S.State) -> S.State:
  match rounds_left win:
    case 0n _:
      state
    case 1n+z W{a, +b, c, d, e, f, +g, h, i, j, l, m, o, r, +t, +u}:
      +w = (small1(b) + g + small0(t) + u : U32)
      kr22(z, W{w, a, b, c, d, e, f, g, h, i, j, l, m, o, r, t}, step(state, 1249150122, w))

# Return the SHA-256 round constant for schedule index 20.
def kr20(rounds_left: Nat, win: ShaWindow, state: S.State) -> S.State:
  match rounds_left win:
    case 0n _:
      state
    case 1n+z W{a, +b, c, d, e, f, +g, h, i, j, l, m, o, r, +t, +u}:
      +w = (small1(b) + g + small0(t) + u : U32)
      kr21(z, W{w, a, b, c, d, e, f, g, h, i, j, l, m, o, r, t}, step(state, 770255983, w))

# Return the SHA-256 round constant for schedule index 19.
def kr19(rounds_left: Nat, win: ShaWindow, state: S.State) -> S.State:
  match rounds_left win:
    case 0n _:
      state
    case 1n+z W{a, +b, c, d, e, f, +g, h, i, j, l, m, o, r, +t, +u}:
      +w = (small1(b) + g + small0(t) + u : U32)
      kr20(z, W{w, a, b, c, d, e, f, g, h, i, j, l, m, o, r, t}, step(state, 604807628, w))

# Return the SHA-256 round constant for schedule index 18.
def kr18(rounds_left: Nat, win: ShaWindow, state: S.State) -> S.State:
  match rounds_left win:
    case 0n _:
      state
    case 1n+z W{a, +b, c, d, e, f, +g, h, i, j, l, m, o, r, +t, +u}:
      +w = (small1(b) + g + small0(t) + u : U32)
      kr19(z, W{w, a, b, c, d, e, f, g, h, i, j, l, m, o, r, t}, step(state, 264347078, w))

# Return the SHA-256 round constant for schedule index 17.
def kr17(rounds_left: Nat, win: ShaWindow, state: S.State) -> S.State:
  match rounds_left win:
    case 0n _:
      state
    case 1n+z W{a, +b, c, d, e, f, +g, h, i, j, l, m, o, r, +t, +u}:
      +w = (small1(b) + g + small0(t) + u : U32)
      kr18(z, W{w, a, b, c, d, e, f, g, h, i, j, l, m, o, r, t}, step(state, 4022224774, w))

# Return the SHA-256 round constant for schedule index 16.
def kr16(rounds_left: Nat, win: ShaWindow, state: S.State) -> S.State:
  match rounds_left win:
    case 0n _:
      state
    case 1n+z W{a, +b, c, d, e, f, +g, h, i, j, l, m, o, r, +t, +u}:
      +w = (small1(b) + g + small0(t) + u : U32)
      kr17(z, W{w, a, b, c, d, e, f, g, h, i, j, l, m, o, r, t}, step(state, 3835390401, w))

# window_compress16 specialized to the FIPS table: no constant list is walked.
def fips_compress16(
  +word_a: U32,
  +word_b: U32,
  +word_c: U32,
  +word_d: U32,
  +word_e: U32,
  +word_f: U32,
  +word_g: U32,
  +word_h: U32,
  +word_i: U32,
  +word_j: U32,
  +round_constant: U32,
  +word_l: U32,
  +word_m: U32,
  +count: U32,
  +word_o: U32,
  +word_p: U32,
  +rounds_left: Nat,
  +state: S.State
) -> S.State:
  s1 = step(state, 1116352408, word_a)
  s2 = step(s1, 1899447441, word_b)
  s3 = step(s2, 3049323471, word_c)
  s4 = step(s3, 3921009573, word_d)
  s5 = step(s4, 961987163, word_e)
  s6 = step(s5, 1508970993, word_f)
  s7 = step(s6, 2453635748, word_g)
  s8 = step(s7, 2870763221, word_h)
  s9 = step(s8, 3624381080, word_i)
  s10 = step(s9, 310598401, word_j)
  s11 = step(s10, 607225278, round_constant)
  s12 = step(s11, 1426881987, word_l)
  s13 = step(s12, 1925078388, word_m)
  s14 = step(s13, 2162078206, count)
  s15 = step(s14, 2614888103, word_o)
  s16 = step(s15, 3248222580, word_p)
  feedforward(state, kr16(rounds_left, W{word_p, word_o, count, word_m, word_l, round_constant, word_j, word_i, word_h, word_g, word_f, word_e, word_d, word_c, word_b, word_a}, s16))

# FIPS padding suffix for a message of n bytes, computed with modular
# arithmetic. The proofs state the streaming hash in terms of it.
def suffix(+byte_length: Nat) -> List<&2, U32>:
  128 <> List.append(&2, U32,
    List.replicate(U32, Nat.mod(Nat.sub(119n, Nat.mod(byte_length, 64n)), 64n), 0), bit_length(byte_length))

# Big-endian words of the 64-bit message bit length 8n, computed from n with
# exactly the digit expressions bit_length produces, but without building and
# matching an eight-element list. bit_length(n) is [o(d6), .., o(d0), low]
# where d0 = n / 32, d(k+1) = dk / 256 and o(x) = x mod 256.
def len_hi(+byte_length: Nat) -> U32:
  +d0 = Nat.div(byte_length, 32n)
  +d1 = Nat.div(d0, 256n)
  +d2 = Nat.div(d1, 256n)
  +d3 = Nat.div(d2, 256n)
  +d4 = Nat.div(d3, 256n)
  +d5 = Nat.div(d4, 256n)
  +d6 = Nat.div(d5, 256n)
  pack(U32.from_nat(Nat.mod(d6, 256n)), U32.from_nat(Nat.mod(d5, 256n)),
    U32.from_nat(Nat.mod(d4, 256n)), U32.from_nat(Nat.mod(d3, 256n)))

# Return the length of lo in the SHA-256 compression implementation.
def len_lo(+byte_length: Nat) -> U32:
  +d0 = Nat.div(byte_length, 32n)
  +d1 = Nat.div(d0, 256n)
  +d2 = Nat.div(d1, 256n)
  pack(U32.from_nat(Nat.mod(d2, 256n)), U32.from_nat(Nat.mod(d1, 256n)),
    U32.from_nat(Nat.mod(d0, 256n)), U32.shln(U32.from_nat(Nat.mod(byte_length, 32n)), 3n))

# Final block(s) for an n-byte message ending in r = 0..63 tail bytes. Each
# tail length has its own padded layout: the tail bytes, the 0x80 marker, the
# zero fill and the big-endian bit length are packed straight into schedule
# words, so no padded list is built.
def fin0(+byte_length: Nat, +extra: Nat, state: S.State) -> S.State:
  fips_compress16(pack(128, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), len_hi(byte_length), len_lo(byte_length),
    extra, state)

# Apply SHA-256 round 1 to the compression state.
def fin1(+t0: U32, +byte_length: Nat, +extra: Nat, state: S.State) -> S.State:
  fips_compress16(pack(t0, 128, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), len_hi(byte_length), len_lo(byte_length),
    extra, state)

# Apply SHA-256 round 2 to the compression state.
def fin2(+t0: U32, +t1: U32, +byte_length: Nat, +extra: Nat, state: S.State) -> S.State:
  fips_compress16(pack(t0, t1, 128, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), len_hi(byte_length), len_lo(byte_length),
    extra, state)

# Apply SHA-256 round 3 to the compression state.
def fin3(+t0: U32, +t1: U32, +t2: U32, +byte_length: Nat, +extra: Nat, state: S.State) -> S.State:
  fips_compress16(pack(t0, t1, t2, 128), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), len_hi(byte_length), len_lo(byte_length),
    extra, state)

# Apply SHA-256 round 4 to the compression state.
def fin4(
  +t0: U32,
  +t1: U32,
  +t2: U32,
  +t3: U32,
  +byte_length: Nat,
  +extra: Nat,
  state: S.State
) -> S.State:
  fips_compress16(pack(t0, t1, t2, t3), pack(128, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), len_hi(byte_length), len_lo(byte_length),
    extra, state)

# Apply SHA-256 round 5 to the compression state.
def fin5(
  +t0: U32,
  +t1: U32,
  +t2: U32,
  +t3: U32,
  +t4: U32,
  +byte_length: Nat,
  +extra: Nat,
  state: S.State
) -> S.State:
  fips_compress16(pack(t0, t1, t2, t3), pack(t4, 128, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), len_hi(byte_length), len_lo(byte_length),
    extra, state)

# Apply SHA-256 round 6 to the compression state.
def fin6(
  +t0: U32,
  +t1: U32,
  +t2: U32,
  +t3: U32,
  +t4: U32,
  +t5: U32,
  +byte_length: Nat,
  +extra: Nat,
  state: S.State
) -> S.State:
  fips_compress16(pack(t0, t1, t2, t3), pack(t4, t5, 128, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), len_hi(byte_length), len_lo(byte_length),
    extra, state)

# Apply SHA-256 round 7 to the compression state.
def fin7(
  +t0: U32,
  +t1: U32,
  +t2: U32,
  +t3: U32,
  +t4: U32,
  +t5: U32,
  +t6: U32,
  +byte_length: Nat,
  +extra: Nat,
  state: S.State
) -> S.State:
  fips_compress16(pack(t0, t1, t2, t3), pack(t4, t5, t6, 128), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), len_hi(byte_length), len_lo(byte_length),
    extra, state)

# Apply SHA-256 round 8 to the compression state.
def fin8(
  +t0: U32,
  +t1: U32,
  +t2: U32,
  +t3: U32,
  +t4: U32,
  +t5: U32,
  +t6: U32,
  +t7: U32,
  +byte_length: Nat,
  +extra: Nat,
  state: S.State
) -> S.State:
  fips_compress16(pack(t0, t1, t2, t3), pack(t4, t5, t6, t7), pack(128, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), len_hi(byte_length), len_lo(byte_length),
    extra, state)

# Apply SHA-256 round 9 to the compression state.
def fin9(
  +t0: U32,
  +t1: U32,
  +t2: U32,
  +t3: U32,
  +t4: U32,
  +t5: U32,
  +t6: U32,
  +t7: U32,
  +t8: U32,
  +byte_length: Nat,
  +extra: Nat,
  state: S.State
) -> S.State:
  fips_compress16(pack(t0, t1, t2, t3), pack(t4, t5, t6, t7), pack(t8, 128, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), len_hi(byte_length), len_lo(byte_length),
    extra, state)

# Apply SHA-256 round 10 to the compression state.
def fin10(
  +t0: U32,
  +t1: U32,
  +t2: U32,
  +t3: U32,
  +t4: U32,
  +t5: U32,
  +t6: U32,
  +t7: U32,
  +t8: U32,
  +t9: U32,
  +byte_length: Nat,
  +extra: Nat,
  state: S.State
) -> S.State:
  fips_compress16(pack(t0, t1, t2, t3), pack(t4, t5, t6, t7), pack(t8, t9, 128, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), len_hi(byte_length), len_lo(byte_length),
    extra, state)

# Apply SHA-256 round 11 to the compression state.
def fin11(
  +t0: U32,
  +t1: U32,
  +t2: U32,
  +t3: U32,
  +t4: U32,
  +t5: U32,
  +t6: U32,
  +t7: U32,
  +t8: U32,
  +t9: U32,
  +t10: U32,
  +byte_length: Nat,
  +extra: Nat,
  state: S.State
) -> S.State:
  fips_compress16(pack(t0, t1, t2, t3), pack(t4, t5, t6, t7), pack(t8, t9, t10, 128), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), len_hi(byte_length), len_lo(byte_length),
    extra, state)

# Apply SHA-256 round 12 to the compression state.
def fin12(
  +t0: U32,
  +t1: U32,
  +t2: U32,
  +t3: U32,
  +t4: U32,
  +t5: U32,
  +t6: U32,
  +t7: U32,
  +t8: U32,
  +t9: U32,
  +t10: U32,
  +t11: U32,
  +byte_length: Nat,
  +extra: Nat,
  state: S.State
) -> S.State:
  fips_compress16(pack(t0, t1, t2, t3), pack(t4, t5, t6, t7), pack(t8, t9, t10, t11), pack(128, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), len_hi(byte_length), len_lo(byte_length),
    extra, state)

# Apply SHA-256 round 13 to the compression state.
def fin13(
  +t0: U32,
  +t1: U32,
  +t2: U32,
  +t3: U32,
  +t4: U32,
  +t5: U32,
  +t6: U32,
  +t7: U32,
  +t8: U32,
  +t9: U32,
  +t10: U32,
  +t11: U32,
  +t12: U32,
  +byte_length: Nat,
  +extra: Nat,
  state: S.State
) -> S.State:
  fips_compress16(pack(t0, t1, t2, t3), pack(t4, t5, t6, t7), pack(t8, t9, t10, t11), pack(t12, 128, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), len_hi(byte_length), len_lo(byte_length),
    extra, state)

# Apply SHA-256 round 14 to the compression state.
def fin14(
  +t0: U32,
  +t1: U32,
  +t2: U32,
  +t3: U32,
  +t4: U32,
  +t5: U32,
  +t6: U32,
  +t7: U32,
  +t8: U32,
  +t9: U32,
  +t10: U32,
  +t11: U32,
  +t12: U32,
  +t13: U32,
  +byte_length: Nat,
  +extra: Nat,
  state: S.State
) -> S.State:
  fips_compress16(pack(t0, t1, t2, t3), pack(t4, t5, t6, t7), pack(t8, t9, t10, t11), pack(t12, t13, 128, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), len_hi(byte_length), len_lo(byte_length),
    extra, state)

# Apply SHA-256 round 15 to the compression state.
def fin15(
  +t0: U32,
  +t1: U32,
  +t2: U32,
  +t3: U32,
  +t4: U32,
  +t5: U32,
  +t6: U32,
  +t7: U32,
  +t8: U32,
  +t9: U32,
  +t10: U32,
  +t11: U32,
  +t12: U32,
  +t13: U32,
  +t14: U32,
  +byte_length: Nat,
  +extra: Nat,
  state: S.State
) -> S.State:
  fips_compress16(pack(t0, t1, t2, t3), pack(t4, t5, t6, t7), pack(t8, t9, t10, t11), pack(t12, t13, t14, 128), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), len_hi(byte_length), len_lo(byte_length),
    extra, state)

# Apply SHA-256 round 16 to the compression state.
def fin16(
  +t0: U32,
  +t1: U32,
  +t2: U32,
  +t3: U32,
  +t4: U32,
  +t5: U32,
  +t6: U32,
  +t7: U32,
  +t8: U32,
  +t9: U32,
  +t10: U32,
  +t11: U32,
  +t12: U32,
  +t13: U32,
  +t14: U32,
  +t15: U32,
  +byte_length: Nat,
  +extra: Nat,
  state: S.State
) -> S.State:
  fips_compress16(pack(t0, t1, t2, t3), pack(t4, t5, t6, t7), pack(t8, t9, t10, t11), pack(t12, t13, t14, t15), pack(128, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), len_hi(byte_length), len_lo(byte_length),
    extra, state)

# Apply SHA-256 round 17 to the compression state.
def fin17(
  +t0: U32,
  +t1: U32,
  +t2: U32,
  +t3: U32,
  +t4: U32,
  +t5: U32,
  +t6: U32,
  +t7: U32,
  +t8: U32,
  +t9: U32,
  +t10: U32,
  +t11: U32,
  +t12: U32,
  +t13: U32,
  +t14: U32,
  +t15: U32,
  +t16: U32,
  +byte_length: Nat,
  +extra: Nat,
  state: S.State
) -> S.State:
  fips_compress16(pack(t0, t1, t2, t3), pack(t4, t5, t6, t7), pack(t8, t9, t10, t11), pack(t12, t13, t14, t15), pack(t16, 128, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), len_hi(byte_length), len_lo(byte_length),
    extra, state)

# Apply SHA-256 round 18 to the compression state.
def fin18(
  +t0: U32,
  +t1: U32,
  +t2: U32,
  +t3: U32,
  +t4: U32,
  +t5: U32,
  +t6: U32,
  +t7: U32,
  +t8: U32,
  +t9: U32,
  +t10: U32,
  +t11: U32,
  +t12: U32,
  +t13: U32,
  +t14: U32,
  +t15: U32,
  +t16: U32,
  +t17: U32,
  +byte_length: Nat,
  +extra: Nat,
  state: S.State
) -> S.State:
  fips_compress16(pack(t0, t1, t2, t3), pack(t4, t5, t6, t7), pack(t8, t9, t10, t11), pack(t12, t13, t14, t15), pack(t16, t17, 128, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), len_hi(byte_length), len_lo(byte_length),
    extra, state)

# Apply SHA-256 round 19 to the compression state.
def fin19(
  +t0: U32,
  +t1: U32,
  +t2: U32,
  +t3: U32,
  +t4: U32,
  +t5: U32,
  +t6: U32,
  +t7: U32,
  +t8: U32,
  +t9: U32,
  +t10: U32,
  +t11: U32,
  +t12: U32,
  +t13: U32,
  +t14: U32,
  +t15: U32,
  +t16: U32,
  +t17: U32,
  +t18: U32,
  +byte_length: Nat,
  +extra: Nat,
  state: S.State
) -> S.State:
  fips_compress16(pack(t0, t1, t2, t3), pack(t4, t5, t6, t7), pack(t8, t9, t10, t11), pack(t12, t13, t14, t15), pack(t16, t17, t18, 128), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), len_hi(byte_length), len_lo(byte_length),
    extra, state)

# Apply SHA-256 round 20 to the compression state.
def fin20(
  +t0: U32,
  +t1: U32,
  +t2: U32,
  +t3: U32,
  +t4: U32,
  +t5: U32,
  +t6: U32,
  +t7: U32,
  +t8: U32,
  +t9: U32,
  +t10: U32,
  +t11: U32,
  +t12: U32,
  +t13: U32,
  +t14: U32,
  +t15: U32,
  +t16: U32,
  +t17: U32,
  +t18: U32,
  +t19: U32,
  +byte_length: Nat,
  +extra: Nat,
  state: S.State
) -> S.State:
  fips_compress16(pack(t0, t1, t2, t3), pack(t4, t5, t6, t7), pack(t8, t9, t10, t11), pack(t12, t13, t14, t15), pack(t16, t17, t18, t19), pack(128, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), len_hi(byte_length), len_lo(byte_length),
    extra, state)

# Apply SHA-256 round 21 to the compression state.
def fin21(
  +t0: U32,
  +t1: U32,
  +t2: U32,
  +t3: U32,
  +t4: U32,
  +t5: U32,
  +t6: U32,
  +t7: U32,
  +t8: U32,
  +t9: U32,
  +t10: U32,
  +t11: U32,
  +t12: U32,
  +t13: U32,
  +t14: U32,
  +t15: U32,
  +t16: U32,
  +t17: U32,
  +t18: U32,
  +t19: U32,
  +t20: U32,
  +byte_length: Nat,
  +extra: Nat,
  state: S.State
) -> S.State:
  fips_compress16(pack(t0, t1, t2, t3), pack(t4, t5, t6, t7), pack(t8, t9, t10, t11), pack(t12, t13, t14, t15), pack(t16, t17, t18, t19), pack(t20, 128, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), len_hi(byte_length), len_lo(byte_length),
    extra, state)

# Apply SHA-256 round 22 to the compression state.
def fin22(
  +t0: U32,
  +t1: U32,
  +t2: U32,
  +t3: U32,
  +t4: U32,
  +t5: U32,
  +t6: U32,
  +t7: U32,
  +t8: U32,
  +t9: U32,
  +t10: U32,
  +t11: U32,
  +t12: U32,
  +t13: U32,
  +t14: U32,
  +t15: U32,
  +t16: U32,
  +t17: U32,
  +t18: U32,
  +t19: U32,
  +t20: U32,
  +t21: U32,
  +byte_length: Nat,
  +extra: Nat,
  state: S.State
) -> S.State:
  fips_compress16(pack(t0, t1, t2, t3), pack(t4, t5, t6, t7), pack(t8, t9, t10, t11), pack(t12, t13, t14, t15), pack(t16, t17, t18, t19), pack(t20, t21, 128, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), len_hi(byte_length), len_lo(byte_length),
    extra, state)

# Apply SHA-256 round 23 to the compression state.
def fin23(
  +t0: U32,
  +t1: U32,
  +t2: U32,
  +t3: U32,
  +t4: U32,
  +t5: U32,
  +t6: U32,
  +t7: U32,
  +t8: U32,
  +t9: U32,
  +t10: U32,
  +t11: U32,
  +t12: U32,
  +t13: U32,
  +t14: U32,
  +t15: U32,
  +t16: U32,
  +t17: U32,
  +t18: U32,
  +t19: U32,
  +t20: U32,
  +t21: U32,
  +t22: U32,
  +byte_length: Nat,
  +extra: Nat,
  state: S.State
) -> S.State:
  fips_compress16(pack(t0, t1, t2, t3), pack(t4, t5, t6, t7), pack(t8, t9, t10, t11), pack(t12, t13, t14, t15), pack(t16, t17, t18, t19), pack(t20, t21, t22, 128), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), len_hi(byte_length), len_lo(byte_length),
    extra, state)

# Apply SHA-256 round 24 to the compression state.
def fin24(
  +t0: U32,
  +t1: U32,
  +t2: U32,
  +t3: U32,
  +t4: U32,
  +t5: U32,
  +t6: U32,
  +t7: U32,
  +t8: U32,
  +t9: U32,
  +t10: U32,
  +t11: U32,
  +t12: U32,
  +t13: U32,
  +t14: U32,
  +t15: U32,
  +t16: U32,
  +t17: U32,
  +t18: U32,
  +t19: U32,
  +t20: U32,
  +t21: U32,
  +t22: U32,
  +t23: U32,
  +byte_length: Nat,
  +extra: Nat,
  state: S.State
) -> S.State:
  fips_compress16(pack(t0, t1, t2, t3), pack(t4, t5, t6, t7), pack(t8, t9, t10, t11), pack(t12, t13, t14, t15), pack(t16, t17, t18, t19), pack(t20, t21, t22, t23), pack(128, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), len_hi(byte_length), len_lo(byte_length),
    extra, state)

# Apply SHA-256 round 25 to the compression state.
def fin25(
  +t0: U32,
  +t1: U32,
  +t2: U32,
  +t3: U32,
  +t4: U32,
  +t5: U32,
  +t6: U32,
  +t7: U32,
  +t8: U32,
  +t9: U32,
  +t10: U32,
  +t11: U32,
  +t12: U32,
  +t13: U32,
  +t14: U32,
  +t15: U32,
  +t16: U32,
  +t17: U32,
  +t18: U32,
  +t19: U32,
  +t20: U32,
  +t21: U32,
  +t22: U32,
  +t23: U32,
  +t24: U32,
  +byte_length: Nat,
  +extra: Nat,
  state: S.State
) -> S.State:
  fips_compress16(pack(t0, t1, t2, t3), pack(t4, t5, t6, t7), pack(t8, t9, t10, t11), pack(t12, t13, t14, t15), pack(t16, t17, t18, t19), pack(t20, t21, t22, t23), pack(t24, 128, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), len_hi(byte_length), len_lo(byte_length),
    extra, state)

# Apply SHA-256 round 26 to the compression state.
def fin26(
  +t0: U32,
  +t1: U32,
  +t2: U32,
  +t3: U32,
  +t4: U32,
  +t5: U32,
  +t6: U32,
  +t7: U32,
  +t8: U32,
  +t9: U32,
  +t10: U32,
  +t11: U32,
  +t12: U32,
  +t13: U32,
  +t14: U32,
  +t15: U32,
  +t16: U32,
  +t17: U32,
  +t18: U32,
  +t19: U32,
  +t20: U32,
  +t21: U32,
  +t22: U32,
  +t23: U32,
  +t24: U32,
  +t25: U32,
  +byte_length: Nat,
  +extra: Nat,
  state: S.State
) -> S.State:
  fips_compress16(pack(t0, t1, t2, t3), pack(t4, t5, t6, t7), pack(t8, t9, t10, t11), pack(t12, t13, t14, t15), pack(t16, t17, t18, t19), pack(t20, t21, t22, t23), pack(t24, t25, 128, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), len_hi(byte_length), len_lo(byte_length),
    extra, state)

# Apply SHA-256 round 27 to the compression state.
def fin27(
  +t0: U32,
  +t1: U32,
  +t2: U32,
  +t3: U32,
  +t4: U32,
  +t5: U32,
  +t6: U32,
  +t7: U32,
  +t8: U32,
  +t9: U32,
  +t10: U32,
  +t11: U32,
  +t12: U32,
  +t13: U32,
  +t14: U32,
  +t15: U32,
  +t16: U32,
  +t17: U32,
  +t18: U32,
  +t19: U32,
  +t20: U32,
  +t21: U32,
  +t22: U32,
  +t23: U32,
  +t24: U32,
  +t25: U32,
  +t26: U32,
  +byte_length: Nat,
  +extra: Nat,
  state: S.State
) -> S.State:
  fips_compress16(pack(t0, t1, t2, t3), pack(t4, t5, t6, t7), pack(t8, t9, t10, t11), pack(t12, t13, t14, t15), pack(t16, t17, t18, t19), pack(t20, t21, t22, t23), pack(t24, t25, t26, 128), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), len_hi(byte_length), len_lo(byte_length),
    extra, state)

# Apply SHA-256 round 28 to the compression state.
def fin28(
  +t0: U32,
  +t1: U32,
  +t2: U32,
  +t3: U32,
  +t4: U32,
  +t5: U32,
  +t6: U32,
  +t7: U32,
  +t8: U32,
  +t9: U32,
  +t10: U32,
  +t11: U32,
  +t12: U32,
  +t13: U32,
  +t14: U32,
  +t15: U32,
  +t16: U32,
  +t17: U32,
  +t18: U32,
  +t19: U32,
  +t20: U32,
  +t21: U32,
  +t22: U32,
  +t23: U32,
  +t24: U32,
  +t25: U32,
  +t26: U32,
  +t27: U32,
  +byte_length: Nat,
  +extra: Nat,
  state: S.State
) -> S.State:
  fips_compress16(pack(t0, t1, t2, t3), pack(t4, t5, t6, t7), pack(t8, t9, t10, t11), pack(t12, t13, t14, t15), pack(t16, t17, t18, t19), pack(t20, t21, t22, t23), pack(t24, t25, t26, t27), pack(128, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), len_hi(byte_length), len_lo(byte_length),
    extra, state)

# Apply SHA-256 round 29 to the compression state.
def fin29(
  +t0: U32,
  +t1: U32,
  +t2: U32,
  +t3: U32,
  +t4: U32,
  +t5: U32,
  +t6: U32,
  +t7: U32,
  +t8: U32,
  +t9: U32,
  +t10: U32,
  +t11: U32,
  +t12: U32,
  +t13: U32,
  +t14: U32,
  +t15: U32,
  +t16: U32,
  +t17: U32,
  +t18: U32,
  +t19: U32,
  +t20: U32,
  +t21: U32,
  +t22: U32,
  +t23: U32,
  +t24: U32,
  +t25: U32,
  +t26: U32,
  +t27: U32,
  +t28: U32,
  +byte_length: Nat,
  +extra: Nat,
  state: S.State
) -> S.State:
  fips_compress16(pack(t0, t1, t2, t3), pack(t4, t5, t6, t7), pack(t8, t9, t10, t11), pack(t12, t13, t14, t15), pack(t16, t17, t18, t19), pack(t20, t21, t22, t23), pack(t24, t25, t26, t27), pack(t28, 128, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), len_hi(byte_length), len_lo(byte_length),
    extra, state)

# Apply SHA-256 round 30 to the compression state.
def fin30(
  +t0: U32,
  +t1: U32,
  +t2: U32,
  +t3: U32,
  +t4: U32,
  +t5: U32,
  +t6: U32,
  +t7: U32,
  +t8: U32,
  +t9: U32,
  +t10: U32,
  +t11: U32,
  +t12: U32,
  +t13: U32,
  +t14: U32,
  +t15: U32,
  +t16: U32,
  +t17: U32,
  +t18: U32,
  +t19: U32,
  +t20: U32,
  +t21: U32,
  +t22: U32,
  +t23: U32,
  +t24: U32,
  +t25: U32,
  +t26: U32,
  +t27: U32,
  +t28: U32,
  +t29: U32,
  +byte_length: Nat,
  +extra: Nat,
  state: S.State
) -> S.State:
  fips_compress16(pack(t0, t1, t2, t3), pack(t4, t5, t6, t7), pack(t8, t9, t10, t11), pack(t12, t13, t14, t15), pack(t16, t17, t18, t19), pack(t20, t21, t22, t23), pack(t24, t25, t26, t27), pack(t28, t29, 128, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), len_hi(byte_length), len_lo(byte_length),
    extra, state)

# Apply SHA-256 round 31 to the compression state.
def fin31(
  +t0: U32,
  +t1: U32,
  +t2: U32,
  +t3: U32,
  +t4: U32,
  +t5: U32,
  +t6: U32,
  +t7: U32,
  +t8: U32,
  +t9: U32,
  +t10: U32,
  +t11: U32,
  +t12: U32,
  +t13: U32,
  +t14: U32,
  +t15: U32,
  +t16: U32,
  +t17: U32,
  +t18: U32,
  +t19: U32,
  +t20: U32,
  +t21: U32,
  +t22: U32,
  +t23: U32,
  +t24: U32,
  +t25: U32,
  +t26: U32,
  +t27: U32,
  +t28: U32,
  +t29: U32,
  +t30: U32,
  +byte_length: Nat,
  +extra: Nat,
  state: S.State
) -> S.State:
  fips_compress16(pack(t0, t1, t2, t3), pack(t4, t5, t6, t7), pack(t8, t9, t10, t11), pack(t12, t13, t14, t15), pack(t16, t17, t18, t19), pack(t20, t21, t22, t23), pack(t24, t25, t26, t27), pack(t28, t29, t30, 128), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), len_hi(byte_length), len_lo(byte_length),
    extra, state)

# Apply SHA-256 round 32 to the compression state.
def fin32(
  +t0: U32,
  +t1: U32,
  +t2: U32,
  +t3: U32,
  +t4: U32,
  +t5: U32,
  +t6: U32,
  +t7: U32,
  +t8: U32,
  +t9: U32,
  +t10: U32,
  +t11: U32,
  +t12: U32,
  +t13: U32,
  +t14: U32,
  +t15: U32,
  +t16: U32,
  +t17: U32,
  +t18: U32,
  +t19: U32,
  +t20: U32,
  +t21: U32,
  +t22: U32,
  +t23: U32,
  +t24: U32,
  +t25: U32,
  +t26: U32,
  +t27: U32,
  +t28: U32,
  +t29: U32,
  +t30: U32,
  +t31: U32,
  +byte_length: Nat,
  +extra: Nat,
  state: S.State
) -> S.State:
  fips_compress16(pack(t0, t1, t2, t3), pack(t4, t5, t6, t7), pack(t8, t9, t10, t11), pack(t12, t13, t14, t15), pack(t16, t17, t18, t19), pack(t20, t21, t22, t23), pack(t24, t25, t26, t27), pack(t28, t29, t30, t31), pack(128, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), len_hi(byte_length), len_lo(byte_length),
    extra, state)

# Apply SHA-256 round 33 to the compression state.
def fin33(
  +t0: U32,
  +t1: U32,
  +t2: U32,
  +t3: U32,
  +t4: U32,
  +t5: U32,
  +t6: U32,
  +t7: U32,
  +t8: U32,
  +t9: U32,
  +t10: U32,
  +t11: U32,
  +t12: U32,
  +t13: U32,
  +t14: U32,
  +t15: U32,
  +t16: U32,
  +t17: U32,
  +t18: U32,
  +t19: U32,
  +t20: U32,
  +t21: U32,
  +t22: U32,
  +t23: U32,
  +t24: U32,
  +t25: U32,
  +t26: U32,
  +t27: U32,
  +t28: U32,
  +t29: U32,
  +t30: U32,
  +t31: U32,
  +t32: U32,
  +byte_length: Nat,
  +extra: Nat,
  state: S.State
) -> S.State:
  fips_compress16(pack(t0, t1, t2, t3), pack(t4, t5, t6, t7), pack(t8, t9, t10, t11), pack(t12, t13, t14, t15), pack(t16, t17, t18, t19), pack(t20, t21, t22, t23), pack(t24, t25, t26, t27), pack(t28, t29, t30, t31), pack(t32, 128, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), len_hi(byte_length), len_lo(byte_length),
    extra, state)

# Apply SHA-256 round 34 to the compression state.
def fin34(
  +t0: U32,
  +t1: U32,
  +t2: U32,
  +t3: U32,
  +t4: U32,
  +t5: U32,
  +t6: U32,
  +t7: U32,
  +t8: U32,
  +t9: U32,
  +t10: U32,
  +t11: U32,
  +t12: U32,
  +t13: U32,
  +t14: U32,
  +t15: U32,
  +t16: U32,
  +t17: U32,
  +t18: U32,
  +t19: U32,
  +t20: U32,
  +t21: U32,
  +t22: U32,
  +t23: U32,
  +t24: U32,
  +t25: U32,
  +t26: U32,
  +t27: U32,
  +t28: U32,
  +t29: U32,
  +t30: U32,
  +t31: U32,
  +t32: U32,
  +t33: U32,
  +byte_length: Nat,
  +extra: Nat,
  state: S.State
) -> S.State:
  fips_compress16(pack(t0, t1, t2, t3), pack(t4, t5, t6, t7), pack(t8, t9, t10, t11), pack(t12, t13, t14, t15), pack(t16, t17, t18, t19), pack(t20, t21, t22, t23), pack(t24, t25, t26, t27), pack(t28, t29, t30, t31), pack(t32, t33, 128, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), len_hi(byte_length), len_lo(byte_length),
    extra, state)

# Apply SHA-256 round 35 to the compression state.
def fin35(
  +t0: U32,
  +t1: U32,
  +t2: U32,
  +t3: U32,
  +t4: U32,
  +t5: U32,
  +t6: U32,
  +t7: U32,
  +t8: U32,
  +t9: U32,
  +t10: U32,
  +t11: U32,
  +t12: U32,
  +t13: U32,
  +t14: U32,
  +t15: U32,
  +t16: U32,
  +t17: U32,
  +t18: U32,
  +t19: U32,
  +t20: U32,
  +t21: U32,
  +t22: U32,
  +t23: U32,
  +t24: U32,
  +t25: U32,
  +t26: U32,
  +t27: U32,
  +t28: U32,
  +t29: U32,
  +t30: U32,
  +t31: U32,
  +t32: U32,
  +t33: U32,
  +t34: U32,
  +byte_length: Nat,
  +extra: Nat,
  state: S.State
) -> S.State:
  fips_compress16(pack(t0, t1, t2, t3), pack(t4, t5, t6, t7), pack(t8, t9, t10, t11), pack(t12, t13, t14, t15), pack(t16, t17, t18, t19), pack(t20, t21, t22, t23), pack(t24, t25, t26, t27), pack(t28, t29, t30, t31), pack(t32, t33, t34, 128), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), len_hi(byte_length), len_lo(byte_length),
    extra, state)

# Apply SHA-256 round 36 to the compression state.
def fin36(
  +t0: U32,
  +t1: U32,
  +t2: U32,
  +t3: U32,
  +t4: U32,
  +t5: U32,
  +t6: U32,
  +t7: U32,
  +t8: U32,
  +t9: U32,
  +t10: U32,
  +t11: U32,
  +t12: U32,
  +t13: U32,
  +t14: U32,
  +t15: U32,
  +t16: U32,
  +t17: U32,
  +t18: U32,
  +t19: U32,
  +t20: U32,
  +t21: U32,
  +t22: U32,
  +t23: U32,
  +t24: U32,
  +t25: U32,
  +t26: U32,
  +t27: U32,
  +t28: U32,
  +t29: U32,
  +t30: U32,
  +t31: U32,
  +t32: U32,
  +t33: U32,
  +t34: U32,
  +t35: U32,
  +byte_length: Nat,
  +extra: Nat,
  state: S.State
) -> S.State:
  fips_compress16(pack(t0, t1, t2, t3), pack(t4, t5, t6, t7), pack(t8, t9, t10, t11), pack(t12, t13, t14, t15), pack(t16, t17, t18, t19), pack(t20, t21, t22, t23), pack(t24, t25, t26, t27), pack(t28, t29, t30, t31), pack(t32, t33, t34, t35), pack(128, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), len_hi(byte_length), len_lo(byte_length),
    extra, state)

# Apply SHA-256 round 37 to the compression state.
def fin37(
  +t0: U32,
  +t1: U32,
  +t2: U32,
  +t3: U32,
  +t4: U32,
  +t5: U32,
  +t6: U32,
  +t7: U32,
  +t8: U32,
  +t9: U32,
  +t10: U32,
  +t11: U32,
  +t12: U32,
  +t13: U32,
  +t14: U32,
  +t15: U32,
  +t16: U32,
  +t17: U32,
  +t18: U32,
  +t19: U32,
  +t20: U32,
  +t21: U32,
  +t22: U32,
  +t23: U32,
  +t24: U32,
  +t25: U32,
  +t26: U32,
  +t27: U32,
  +t28: U32,
  +t29: U32,
  +t30: U32,
  +t31: U32,
  +t32: U32,
  +t33: U32,
  +t34: U32,
  +t35: U32,
  +t36: U32,
  +byte_length: Nat,
  +extra: Nat,
  state: S.State
) -> S.State:
  fips_compress16(pack(t0, t1, t2, t3), pack(t4, t5, t6, t7), pack(t8, t9, t10, t11), pack(t12, t13, t14, t15), pack(t16, t17, t18, t19), pack(t20, t21, t22, t23), pack(t24, t25, t26, t27), pack(t28, t29, t30, t31), pack(t32, t33, t34, t35), pack(t36, 128, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), len_hi(byte_length), len_lo(byte_length),
    extra, state)

# Apply SHA-256 round 38 to the compression state.
def fin38(
  +t0: U32,
  +t1: U32,
  +t2: U32,
  +t3: U32,
  +t4: U32,
  +t5: U32,
  +t6: U32,
  +t7: U32,
  +t8: U32,
  +t9: U32,
  +t10: U32,
  +t11: U32,
  +t12: U32,
  +t13: U32,
  +t14: U32,
  +t15: U32,
  +t16: U32,
  +t17: U32,
  +t18: U32,
  +t19: U32,
  +t20: U32,
  +t21: U32,
  +t22: U32,
  +t23: U32,
  +t24: U32,
  +t25: U32,
  +t26: U32,
  +t27: U32,
  +t28: U32,
  +t29: U32,
  +t30: U32,
  +t31: U32,
  +t32: U32,
  +t33: U32,
  +t34: U32,
  +t35: U32,
  +t36: U32,
  +t37: U32,
  +byte_length: Nat,
  +extra: Nat,
  state: S.State
) -> S.State:
  fips_compress16(pack(t0, t1, t2, t3), pack(t4, t5, t6, t7), pack(t8, t9, t10, t11), pack(t12, t13, t14, t15), pack(t16, t17, t18, t19), pack(t20, t21, t22, t23), pack(t24, t25, t26, t27), pack(t28, t29, t30, t31), pack(t32, t33, t34, t35), pack(t36, t37, 128, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), len_hi(byte_length), len_lo(byte_length),
    extra, state)

# Apply SHA-256 round 39 to the compression state.
def fin39(
  +t0: U32,
  +t1: U32,
  +t2: U32,
  +t3: U32,
  +t4: U32,
  +t5: U32,
  +t6: U32,
  +t7: U32,
  +t8: U32,
  +t9: U32,
  +t10: U32,
  +t11: U32,
  +t12: U32,
  +t13: U32,
  +t14: U32,
  +t15: U32,
  +t16: U32,
  +t17: U32,
  +t18: U32,
  +t19: U32,
  +t20: U32,
  +t21: U32,
  +t22: U32,
  +t23: U32,
  +t24: U32,
  +t25: U32,
  +t26: U32,
  +t27: U32,
  +t28: U32,
  +t29: U32,
  +t30: U32,
  +t31: U32,
  +t32: U32,
  +t33: U32,
  +t34: U32,
  +t35: U32,
  +t36: U32,
  +t37: U32,
  +t38: U32,
  +byte_length: Nat,
  +extra: Nat,
  state: S.State
) -> S.State:
  fips_compress16(pack(t0, t1, t2, t3), pack(t4, t5, t6, t7), pack(t8, t9, t10, t11), pack(t12, t13, t14, t15), pack(t16, t17, t18, t19), pack(t20, t21, t22, t23), pack(t24, t25, t26, t27), pack(t28, t29, t30, t31), pack(t32, t33, t34, t35), pack(t36, t37, t38, 128), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), len_hi(byte_length), len_lo(byte_length),
    extra, state)

# Apply SHA-256 round 40 to the compression state.
def fin40(
  +t0: U32,
  +t1: U32,
  +t2: U32,
  +t3: U32,
  +t4: U32,
  +t5: U32,
  +t6: U32,
  +t7: U32,
  +t8: U32,
  +t9: U32,
  +t10: U32,
  +t11: U32,
  +t12: U32,
  +t13: U32,
  +t14: U32,
  +t15: U32,
  +t16: U32,
  +t17: U32,
  +t18: U32,
  +t19: U32,
  +t20: U32,
  +t21: U32,
  +t22: U32,
  +t23: U32,
  +t24: U32,
  +t25: U32,
  +t26: U32,
  +t27: U32,
  +t28: U32,
  +t29: U32,
  +t30: U32,
  +t31: U32,
  +t32: U32,
  +t33: U32,
  +t34: U32,
  +t35: U32,
  +t36: U32,
  +t37: U32,
  +t38: U32,
  +t39: U32,
  +byte_length: Nat,
  +extra: Nat,
  state: S.State
) -> S.State:
  fips_compress16(pack(t0, t1, t2, t3), pack(t4, t5, t6, t7), pack(t8, t9, t10, t11), pack(t12, t13, t14, t15), pack(t16, t17, t18, t19), pack(t20, t21, t22, t23), pack(t24, t25, t26, t27), pack(t28, t29, t30, t31), pack(t32, t33, t34, t35), pack(t36, t37, t38, t39), pack(128, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), len_hi(byte_length), len_lo(byte_length),
    extra, state)

# Apply SHA-256 round 41 to the compression state.
def fin41(
  +t0: U32,
  +t1: U32,
  +t2: U32,
  +t3: U32,
  +t4: U32,
  +t5: U32,
  +t6: U32,
  +t7: U32,
  +t8: U32,
  +t9: U32,
  +t10: U32,
  +t11: U32,
  +t12: U32,
  +t13: U32,
  +t14: U32,
  +t15: U32,
  +t16: U32,
  +t17: U32,
  +t18: U32,
  +t19: U32,
  +t20: U32,
  +t21: U32,
  +t22: U32,
  +t23: U32,
  +t24: U32,
  +t25: U32,
  +t26: U32,
  +t27: U32,
  +t28: U32,
  +t29: U32,
  +t30: U32,
  +t31: U32,
  +t32: U32,
  +t33: U32,
  +t34: U32,
  +t35: U32,
  +t36: U32,
  +t37: U32,
  +t38: U32,
  +t39: U32,
  +t40: U32,
  +byte_length: Nat,
  +extra: Nat,
  state: S.State
) -> S.State:
  fips_compress16(pack(t0, t1, t2, t3), pack(t4, t5, t6, t7), pack(t8, t9, t10, t11), pack(t12, t13, t14, t15), pack(t16, t17, t18, t19), pack(t20, t21, t22, t23), pack(t24, t25, t26, t27), pack(t28, t29, t30, t31), pack(t32, t33, t34, t35), pack(t36, t37, t38, t39), pack(t40, 128, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), len_hi(byte_length), len_lo(byte_length),
    extra, state)

# Apply SHA-256 round 42 to the compression state.
def fin42(
  +t0: U32,
  +t1: U32,
  +t2: U32,
  +t3: U32,
  +t4: U32,
  +t5: U32,
  +t6: U32,
  +t7: U32,
  +t8: U32,
  +t9: U32,
  +t10: U32,
  +t11: U32,
  +t12: U32,
  +t13: U32,
  +t14: U32,
  +t15: U32,
  +t16: U32,
  +t17: U32,
  +t18: U32,
  +t19: U32,
  +t20: U32,
  +t21: U32,
  +t22: U32,
  +t23: U32,
  +t24: U32,
  +t25: U32,
  +t26: U32,
  +t27: U32,
  +t28: U32,
  +t29: U32,
  +t30: U32,
  +t31: U32,
  +t32: U32,
  +t33: U32,
  +t34: U32,
  +t35: U32,
  +t36: U32,
  +t37: U32,
  +t38: U32,
  +t39: U32,
  +t40: U32,
  +t41: U32,
  +byte_length: Nat,
  +extra: Nat,
  state: S.State
) -> S.State:
  fips_compress16(pack(t0, t1, t2, t3), pack(t4, t5, t6, t7), pack(t8, t9, t10, t11), pack(t12, t13, t14, t15), pack(t16, t17, t18, t19), pack(t20, t21, t22, t23), pack(t24, t25, t26, t27), pack(t28, t29, t30, t31), pack(t32, t33, t34, t35), pack(t36, t37, t38, t39), pack(t40, t41, 128, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), len_hi(byte_length), len_lo(byte_length),
    extra, state)

# Apply SHA-256 round 43 to the compression state.
def fin43(
  +t0: U32,
  +t1: U32,
  +t2: U32,
  +t3: U32,
  +t4: U32,
  +t5: U32,
  +t6: U32,
  +t7: U32,
  +t8: U32,
  +t9: U32,
  +t10: U32,
  +t11: U32,
  +t12: U32,
  +t13: U32,
  +t14: U32,
  +t15: U32,
  +t16: U32,
  +t17: U32,
  +t18: U32,
  +t19: U32,
  +t20: U32,
  +t21: U32,
  +t22: U32,
  +t23: U32,
  +t24: U32,
  +t25: U32,
  +t26: U32,
  +t27: U32,
  +t28: U32,
  +t29: U32,
  +t30: U32,
  +t31: U32,
  +t32: U32,
  +t33: U32,
  +t34: U32,
  +t35: U32,
  +t36: U32,
  +t37: U32,
  +t38: U32,
  +t39: U32,
  +t40: U32,
  +t41: U32,
  +t42: U32,
  +byte_length: Nat,
  +extra: Nat,
  state: S.State
) -> S.State:
  fips_compress16(pack(t0, t1, t2, t3), pack(t4, t5, t6, t7), pack(t8, t9, t10, t11), pack(t12, t13, t14, t15), pack(t16, t17, t18, t19), pack(t20, t21, t22, t23), pack(t24, t25, t26, t27), pack(t28, t29, t30, t31), pack(t32, t33, t34, t35), pack(t36, t37, t38, t39), pack(t40, t41, t42, 128), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), len_hi(byte_length), len_lo(byte_length),
    extra, state)

# Apply SHA-256 round 44 to the compression state.
def fin44(
  +t0: U32,
  +t1: U32,
  +t2: U32,
  +t3: U32,
  +t4: U32,
  +t5: U32,
  +t6: U32,
  +t7: U32,
  +t8: U32,
  +t9: U32,
  +t10: U32,
  +t11: U32,
  +t12: U32,
  +t13: U32,
  +t14: U32,
  +t15: U32,
  +t16: U32,
  +t17: U32,
  +t18: U32,
  +t19: U32,
  +t20: U32,
  +t21: U32,
  +t22: U32,
  +t23: U32,
  +t24: U32,
  +t25: U32,
  +t26: U32,
  +t27: U32,
  +t28: U32,
  +t29: U32,
  +t30: U32,
  +t31: U32,
  +t32: U32,
  +t33: U32,
  +t34: U32,
  +t35: U32,
  +t36: U32,
  +t37: U32,
  +t38: U32,
  +t39: U32,
  +t40: U32,
  +t41: U32,
  +t42: U32,
  +t43: U32,
  +byte_length: Nat,
  +extra: Nat,
  state: S.State
) -> S.State:
  fips_compress16(pack(t0, t1, t2, t3), pack(t4, t5, t6, t7), pack(t8, t9, t10, t11), pack(t12, t13, t14, t15), pack(t16, t17, t18, t19), pack(t20, t21, t22, t23), pack(t24, t25, t26, t27), pack(t28, t29, t30, t31), pack(t32, t33, t34, t35), pack(t36, t37, t38, t39), pack(t40, t41, t42, t43), pack(128, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), len_hi(byte_length), len_lo(byte_length),
    extra, state)

# Apply SHA-256 round 45 to the compression state.
def fin45(
  +t0: U32,
  +t1: U32,
  +t2: U32,
  +t3: U32,
  +t4: U32,
  +t5: U32,
  +t6: U32,
  +t7: U32,
  +t8: U32,
  +t9: U32,
  +t10: U32,
  +t11: U32,
  +t12: U32,
  +t13: U32,
  +t14: U32,
  +t15: U32,
  +t16: U32,
  +t17: U32,
  +t18: U32,
  +t19: U32,
  +t20: U32,
  +t21: U32,
  +t22: U32,
  +t23: U32,
  +t24: U32,
  +t25: U32,
  +t26: U32,
  +t27: U32,
  +t28: U32,
  +t29: U32,
  +t30: U32,
  +t31: U32,
  +t32: U32,
  +t33: U32,
  +t34: U32,
  +t35: U32,
  +t36: U32,
  +t37: U32,
  +t38: U32,
  +t39: U32,
  +t40: U32,
  +t41: U32,
  +t42: U32,
  +t43: U32,
  +t44: U32,
  +byte_length: Nat,
  +extra: Nat,
  state: S.State
) -> S.State:
  fips_compress16(pack(t0, t1, t2, t3), pack(t4, t5, t6, t7), pack(t8, t9, t10, t11), pack(t12, t13, t14, t15), pack(t16, t17, t18, t19), pack(t20, t21, t22, t23), pack(t24, t25, t26, t27), pack(t28, t29, t30, t31), pack(t32, t33, t34, t35), pack(t36, t37, t38, t39), pack(t40, t41, t42, t43), pack(t44, 128, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), len_hi(byte_length), len_lo(byte_length),
    extra, state)

# Apply SHA-256 round 46 to the compression state.
def fin46(
  +t0: U32,
  +t1: U32,
  +t2: U32,
  +t3: U32,
  +t4: U32,
  +t5: U32,
  +t6: U32,
  +t7: U32,
  +t8: U32,
  +t9: U32,
  +t10: U32,
  +t11: U32,
  +t12: U32,
  +t13: U32,
  +t14: U32,
  +t15: U32,
  +t16: U32,
  +t17: U32,
  +t18: U32,
  +t19: U32,
  +t20: U32,
  +t21: U32,
  +t22: U32,
  +t23: U32,
  +t24: U32,
  +t25: U32,
  +t26: U32,
  +t27: U32,
  +t28: U32,
  +t29: U32,
  +t30: U32,
  +t31: U32,
  +t32: U32,
  +t33: U32,
  +t34: U32,
  +t35: U32,
  +t36: U32,
  +t37: U32,
  +t38: U32,
  +t39: U32,
  +t40: U32,
  +t41: U32,
  +t42: U32,
  +t43: U32,
  +t44: U32,
  +t45: U32,
  +byte_length: Nat,
  +extra: Nat,
  state: S.State
) -> S.State:
  fips_compress16(pack(t0, t1, t2, t3), pack(t4, t5, t6, t7), pack(t8, t9, t10, t11), pack(t12, t13, t14, t15), pack(t16, t17, t18, t19), pack(t20, t21, t22, t23), pack(t24, t25, t26, t27), pack(t28, t29, t30, t31), pack(t32, t33, t34, t35), pack(t36, t37, t38, t39), pack(t40, t41, t42, t43), pack(t44, t45, 128, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), len_hi(byte_length), len_lo(byte_length),
    extra, state)

# Apply SHA-256 round 47 to the compression state.
def fin47(
  +t0: U32,
  +t1: U32,
  +t2: U32,
  +t3: U32,
  +t4: U32,
  +t5: U32,
  +t6: U32,
  +t7: U32,
  +t8: U32,
  +t9: U32,
  +t10: U32,
  +t11: U32,
  +t12: U32,
  +t13: U32,
  +t14: U32,
  +t15: U32,
  +t16: U32,
  +t17: U32,
  +t18: U32,
  +t19: U32,
  +t20: U32,
  +t21: U32,
  +t22: U32,
  +t23: U32,
  +t24: U32,
  +t25: U32,
  +t26: U32,
  +t27: U32,
  +t28: U32,
  +t29: U32,
  +t30: U32,
  +t31: U32,
  +t32: U32,
  +t33: U32,
  +t34: U32,
  +t35: U32,
  +t36: U32,
  +t37: U32,
  +t38: U32,
  +t39: U32,
  +t40: U32,
  +t41: U32,
  +t42: U32,
  +t43: U32,
  +t44: U32,
  +t45: U32,
  +t46: U32,
  +byte_length: Nat,
  +extra: Nat,
  state: S.State
) -> S.State:
  fips_compress16(pack(t0, t1, t2, t3), pack(t4, t5, t6, t7), pack(t8, t9, t10, t11), pack(t12, t13, t14, t15), pack(t16, t17, t18, t19), pack(t20, t21, t22, t23), pack(t24, t25, t26, t27), pack(t28, t29, t30, t31), pack(t32, t33, t34, t35), pack(t36, t37, t38, t39), pack(t40, t41, t42, t43), pack(t44, t45, t46, 128), pack(0, 0, 0, 0), pack(0, 0, 0, 0), len_hi(byte_length), len_lo(byte_length),
    extra, state)

# Apply SHA-256 round 48 to the compression state.
def fin48(
  +t0: U32,
  +t1: U32,
  +t2: U32,
  +t3: U32,
  +t4: U32,
  +t5: U32,
  +t6: U32,
  +t7: U32,
  +t8: U32,
  +t9: U32,
  +t10: U32,
  +t11: U32,
  +t12: U32,
  +t13: U32,
  +t14: U32,
  +t15: U32,
  +t16: U32,
  +t17: U32,
  +t18: U32,
  +t19: U32,
  +t20: U32,
  +t21: U32,
  +t22: U32,
  +t23: U32,
  +t24: U32,
  +t25: U32,
  +t26: U32,
  +t27: U32,
  +t28: U32,
  +t29: U32,
  +t30: U32,
  +t31: U32,
  +t32: U32,
  +t33: U32,
  +t34: U32,
  +t35: U32,
  +t36: U32,
  +t37: U32,
  +t38: U32,
  +t39: U32,
  +t40: U32,
  +t41: U32,
  +t42: U32,
  +t43: U32,
  +t44: U32,
  +t45: U32,
  +t46: U32,
  +t47: U32,
  +byte_length: Nat,
  +extra: Nat,
  state: S.State
) -> S.State:
  fips_compress16(pack(t0, t1, t2, t3), pack(t4, t5, t6, t7), pack(t8, t9, t10, t11), pack(t12, t13, t14, t15), pack(t16, t17, t18, t19), pack(t20, t21, t22, t23), pack(t24, t25, t26, t27), pack(t28, t29, t30, t31), pack(t32, t33, t34, t35), pack(t36, t37, t38, t39), pack(t40, t41, t42, t43), pack(t44, t45, t46, t47), pack(128, 0, 0, 0), pack(0, 0, 0, 0), len_hi(byte_length), len_lo(byte_length),
    extra, state)

# Apply SHA-256 round 49 to the compression state.
def fin49(
  +t0: U32,
  +t1: U32,
  +t2: U32,
  +t3: U32,
  +t4: U32,
  +t5: U32,
  +t6: U32,
  +t7: U32,
  +t8: U32,
  +t9: U32,
  +t10: U32,
  +t11: U32,
  +t12: U32,
  +t13: U32,
  +t14: U32,
  +t15: U32,
  +t16: U32,
  +t17: U32,
  +t18: U32,
  +t19: U32,
  +t20: U32,
  +t21: U32,
  +t22: U32,
  +t23: U32,
  +t24: U32,
  +t25: U32,
  +t26: U32,
  +t27: U32,
  +t28: U32,
  +t29: U32,
  +t30: U32,
  +t31: U32,
  +t32: U32,
  +t33: U32,
  +t34: U32,
  +t35: U32,
  +t36: U32,
  +t37: U32,
  +t38: U32,
  +t39: U32,
  +t40: U32,
  +t41: U32,
  +t42: U32,
  +t43: U32,
  +t44: U32,
  +t45: U32,
  +t46: U32,
  +t47: U32,
  +t48: U32,
  +byte_length: Nat,
  +extra: Nat,
  state: S.State
) -> S.State:
  fips_compress16(pack(t0, t1, t2, t3), pack(t4, t5, t6, t7), pack(t8, t9, t10, t11), pack(t12, t13, t14, t15), pack(t16, t17, t18, t19), pack(t20, t21, t22, t23), pack(t24, t25, t26, t27), pack(t28, t29, t30, t31), pack(t32, t33, t34, t35), pack(t36, t37, t38, t39), pack(t40, t41, t42, t43), pack(t44, t45, t46, t47), pack(t48, 128, 0, 0), pack(0, 0, 0, 0), len_hi(byte_length), len_lo(byte_length),
    extra, state)

# Apply SHA-256 round 50 to the compression state.
def fin50(
  +t0: U32,
  +t1: U32,
  +t2: U32,
  +t3: U32,
  +t4: U32,
  +t5: U32,
  +t6: U32,
  +t7: U32,
  +t8: U32,
  +t9: U32,
  +t10: U32,
  +t11: U32,
  +t12: U32,
  +t13: U32,
  +t14: U32,
  +t15: U32,
  +t16: U32,
  +t17: U32,
  +t18: U32,
  +t19: U32,
  +t20: U32,
  +t21: U32,
  +t22: U32,
  +t23: U32,
  +t24: U32,
  +t25: U32,
  +t26: U32,
  +t27: U32,
  +t28: U32,
  +t29: U32,
  +t30: U32,
  +t31: U32,
  +t32: U32,
  +t33: U32,
  +t34: U32,
  +t35: U32,
  +t36: U32,
  +t37: U32,
  +t38: U32,
  +t39: U32,
  +t40: U32,
  +t41: U32,
  +t42: U32,
  +t43: U32,
  +t44: U32,
  +t45: U32,
  +t46: U32,
  +t47: U32,
  +t48: U32,
  +t49: U32,
  +byte_length: Nat,
  +extra: Nat,
  state: S.State
) -> S.State:
  fips_compress16(pack(t0, t1, t2, t3), pack(t4, t5, t6, t7), pack(t8, t9, t10, t11), pack(t12, t13, t14, t15), pack(t16, t17, t18, t19), pack(t20, t21, t22, t23), pack(t24, t25, t26, t27), pack(t28, t29, t30, t31), pack(t32, t33, t34, t35), pack(t36, t37, t38, t39), pack(t40, t41, t42, t43), pack(t44, t45, t46, t47), pack(t48, t49, 128, 0), pack(0, 0, 0, 0), len_hi(byte_length), len_lo(byte_length),
    extra, state)

# Apply SHA-256 round 51 to the compression state.
def fin51(
  +t0: U32,
  +t1: U32,
  +t2: U32,
  +t3: U32,
  +t4: U32,
  +t5: U32,
  +t6: U32,
  +t7: U32,
  +t8: U32,
  +t9: U32,
  +t10: U32,
  +t11: U32,
  +t12: U32,
  +t13: U32,
  +t14: U32,
  +t15: U32,
  +t16: U32,
  +t17: U32,
  +t18: U32,
  +t19: U32,
  +t20: U32,
  +t21: U32,
  +t22: U32,
  +t23: U32,
  +t24: U32,
  +t25: U32,
  +t26: U32,
  +t27: U32,
  +t28: U32,
  +t29: U32,
  +t30: U32,
  +t31: U32,
  +t32: U32,
  +t33: U32,
  +t34: U32,
  +t35: U32,
  +t36: U32,
  +t37: U32,
  +t38: U32,
  +t39: U32,
  +t40: U32,
  +t41: U32,
  +t42: U32,
  +t43: U32,
  +t44: U32,
  +t45: U32,
  +t46: U32,
  +t47: U32,
  +t48: U32,
  +t49: U32,
  +t50: U32,
  +byte_length: Nat,
  +extra: Nat,
  state: S.State
) -> S.State:
  fips_compress16(pack(t0, t1, t2, t3), pack(t4, t5, t6, t7), pack(t8, t9, t10, t11), pack(t12, t13, t14, t15), pack(t16, t17, t18, t19), pack(t20, t21, t22, t23), pack(t24, t25, t26, t27), pack(t28, t29, t30, t31), pack(t32, t33, t34, t35), pack(t36, t37, t38, t39), pack(t40, t41, t42, t43), pack(t44, t45, t46, t47), pack(t48, t49, t50, 128), pack(0, 0, 0, 0), len_hi(byte_length), len_lo(byte_length),
    extra, state)

# Apply SHA-256 round 52 to the compression state.
def fin52(
  +t0: U32,
  +t1: U32,
  +t2: U32,
  +t3: U32,
  +t4: U32,
  +t5: U32,
  +t6: U32,
  +t7: U32,
  +t8: U32,
  +t9: U32,
  +t10: U32,
  +t11: U32,
  +t12: U32,
  +t13: U32,
  +t14: U32,
  +t15: U32,
  +t16: U32,
  +t17: U32,
  +t18: U32,
  +t19: U32,
  +t20: U32,
  +t21: U32,
  +t22: U32,
  +t23: U32,
  +t24: U32,
  +t25: U32,
  +t26: U32,
  +t27: U32,
  +t28: U32,
  +t29: U32,
  +t30: U32,
  +t31: U32,
  +t32: U32,
  +t33: U32,
  +t34: U32,
  +t35: U32,
  +t36: U32,
  +t37: U32,
  +t38: U32,
  +t39: U32,
  +t40: U32,
  +t41: U32,
  +t42: U32,
  +t43: U32,
  +t44: U32,
  +t45: U32,
  +t46: U32,
  +t47: U32,
  +t48: U32,
  +t49: U32,
  +t50: U32,
  +t51: U32,
  +byte_length: Nat,
  +extra: Nat,
  state: S.State
) -> S.State:
  fips_compress16(pack(t0, t1, t2, t3), pack(t4, t5, t6, t7), pack(t8, t9, t10, t11), pack(t12, t13, t14, t15), pack(t16, t17, t18, t19), pack(t20, t21, t22, t23), pack(t24, t25, t26, t27), pack(t28, t29, t30, t31), pack(t32, t33, t34, t35), pack(t36, t37, t38, t39), pack(t40, t41, t42, t43), pack(t44, t45, t46, t47), pack(t48, t49, t50, t51), pack(128, 0, 0, 0), len_hi(byte_length), len_lo(byte_length),
    extra, state)

# Apply SHA-256 round 53 to the compression state.
def fin53(
  +t0: U32,
  +t1: U32,
  +t2: U32,
  +t3: U32,
  +t4: U32,
  +t5: U32,
  +t6: U32,
  +t7: U32,
  +t8: U32,
  +t9: U32,
  +t10: U32,
  +t11: U32,
  +t12: U32,
  +t13: U32,
  +t14: U32,
  +t15: U32,
  +t16: U32,
  +t17: U32,
  +t18: U32,
  +t19: U32,
  +t20: U32,
  +t21: U32,
  +t22: U32,
  +t23: U32,
  +t24: U32,
  +t25: U32,
  +t26: U32,
  +t27: U32,
  +t28: U32,
  +t29: U32,
  +t30: U32,
  +t31: U32,
  +t32: U32,
  +t33: U32,
  +t34: U32,
  +t35: U32,
  +t36: U32,
  +t37: U32,
  +t38: U32,
  +t39: U32,
  +t40: U32,
  +t41: U32,
  +t42: U32,
  +t43: U32,
  +t44: U32,
  +t45: U32,
  +t46: U32,
  +t47: U32,
  +t48: U32,
  +t49: U32,
  +t50: U32,
  +t51: U32,
  +t52: U32,
  +byte_length: Nat,
  +extra: Nat,
  state: S.State
) -> S.State:
  fips_compress16(pack(t0, t1, t2, t3), pack(t4, t5, t6, t7), pack(t8, t9, t10, t11), pack(t12, t13, t14, t15), pack(t16, t17, t18, t19), pack(t20, t21, t22, t23), pack(t24, t25, t26, t27), pack(t28, t29, t30, t31), pack(t32, t33, t34, t35), pack(t36, t37, t38, t39), pack(t40, t41, t42, t43), pack(t44, t45, t46, t47), pack(t48, t49, t50, t51), pack(t52, 128, 0, 0), len_hi(byte_length), len_lo(byte_length),
    extra, state)

# Apply SHA-256 round 54 to the compression state.
def fin54(
  +t0: U32,
  +t1: U32,
  +t2: U32,
  +t3: U32,
  +t4: U32,
  +t5: U32,
  +t6: U32,
  +t7: U32,
  +t8: U32,
  +t9: U32,
  +t10: U32,
  +t11: U32,
  +t12: U32,
  +t13: U32,
  +t14: U32,
  +t15: U32,
  +t16: U32,
  +t17: U32,
  +t18: U32,
  +t19: U32,
  +t20: U32,
  +t21: U32,
  +t22: U32,
  +t23: U32,
  +t24: U32,
  +t25: U32,
  +t26: U32,
  +t27: U32,
  +t28: U32,
  +t29: U32,
  +t30: U32,
  +t31: U32,
  +t32: U32,
  +t33: U32,
  +t34: U32,
  +t35: U32,
  +t36: U32,
  +t37: U32,
  +t38: U32,
  +t39: U32,
  +t40: U32,
  +t41: U32,
  +t42: U32,
  +t43: U32,
  +t44: U32,
  +t45: U32,
  +t46: U32,
  +t47: U32,
  +t48: U32,
  +t49: U32,
  +t50: U32,
  +t51: U32,
  +t52: U32,
  +t53: U32,
  +byte_length: Nat,
  +extra: Nat,
  state: S.State
) -> S.State:
  fips_compress16(pack(t0, t1, t2, t3), pack(t4, t5, t6, t7), pack(t8, t9, t10, t11), pack(t12, t13, t14, t15), pack(t16, t17, t18, t19), pack(t20, t21, t22, t23), pack(t24, t25, t26, t27), pack(t28, t29, t30, t31), pack(t32, t33, t34, t35), pack(t36, t37, t38, t39), pack(t40, t41, t42, t43), pack(t44, t45, t46, t47), pack(t48, t49, t50, t51), pack(t52, t53, 128, 0), len_hi(byte_length), len_lo(byte_length),
    extra, state)

# Apply SHA-256 round 55 to the compression state.
def fin55(
  +t0: U32,
  +t1: U32,
  +t2: U32,
  +t3: U32,
  +t4: U32,
  +t5: U32,
  +t6: U32,
  +t7: U32,
  +t8: U32,
  +t9: U32,
  +t10: U32,
  +t11: U32,
  +t12: U32,
  +t13: U32,
  +t14: U32,
  +t15: U32,
  +t16: U32,
  +t17: U32,
  +t18: U32,
  +t19: U32,
  +t20: U32,
  +t21: U32,
  +t22: U32,
  +t23: U32,
  +t24: U32,
  +t25: U32,
  +t26: U32,
  +t27: U32,
  +t28: U32,
  +t29: U32,
  +t30: U32,
  +t31: U32,
  +t32: U32,
  +t33: U32,
  +t34: U32,
  +t35: U32,
  +t36: U32,
  +t37: U32,
  +t38: U32,
  +t39: U32,
  +t40: U32,
  +t41: U32,
  +t42: U32,
  +t43: U32,
  +t44: U32,
  +t45: U32,
  +t46: U32,
  +t47: U32,
  +t48: U32,
  +t49: U32,
  +t50: U32,
  +t51: U32,
  +t52: U32,
  +t53: U32,
  +t54: U32,
  +byte_length: Nat,
  +extra: Nat,
  state: S.State
) -> S.State:
  fips_compress16(pack(t0, t1, t2, t3), pack(t4, t5, t6, t7), pack(t8, t9, t10, t11), pack(t12, t13, t14, t15), pack(t16, t17, t18, t19), pack(t20, t21, t22, t23), pack(t24, t25, t26, t27), pack(t28, t29, t30, t31), pack(t32, t33, t34, t35), pack(t36, t37, t38, t39), pack(t40, t41, t42, t43), pack(t44, t45, t46, t47), pack(t48, t49, t50, t51), pack(t52, t53, t54, 128), len_hi(byte_length), len_lo(byte_length),
    extra, state)

# Apply SHA-256 round 56 to the compression state.
def fin56(
  +t0: U32,
  +t1: U32,
  +t2: U32,
  +t3: U32,
  +t4: U32,
  +t5: U32,
  +t6: U32,
  +t7: U32,
  +t8: U32,
  +t9: U32,
  +t10: U32,
  +t11: U32,
  +t12: U32,
  +t13: U32,
  +t14: U32,
  +t15: U32,
  +t16: U32,
  +t17: U32,
  +t18: U32,
  +t19: U32,
  +t20: U32,
  +t21: U32,
  +t22: U32,
  +t23: U32,
  +t24: U32,
  +t25: U32,
  +t26: U32,
  +t27: U32,
  +t28: U32,
  +t29: U32,
  +t30: U32,
  +t31: U32,
  +t32: U32,
  +t33: U32,
  +t34: U32,
  +t35: U32,
  +t36: U32,
  +t37: U32,
  +t38: U32,
  +t39: U32,
  +t40: U32,
  +t41: U32,
  +t42: U32,
  +t43: U32,
  +t44: U32,
  +t45: U32,
  +t46: U32,
  +t47: U32,
  +t48: U32,
  +t49: U32,
  +t50: U32,
  +t51: U32,
  +t52: U32,
  +t53: U32,
  +t54: U32,
  +t55: U32,
  +byte_length: Nat,
  +extra: Nat,
  state: S.State
) -> S.State:
  fips_compress16(pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), len_hi(byte_length), len_lo(byte_length),
    extra, fips_compress16(pack(t0, t1, t2, t3), pack(t4, t5, t6, t7), pack(t8, t9, t10, t11), pack(t12, t13, t14, t15), pack(t16, t17, t18, t19), pack(t20, t21, t22, t23), pack(t24, t25, t26, t27), pack(t28, t29, t30, t31), pack(t32, t33, t34, t35), pack(t36, t37, t38, t39), pack(t40, t41, t42, t43), pack(t44, t45, t46, t47), pack(t48, t49, t50, t51), pack(t52, t53, t54, t55), pack(128, 0, 0, 0), pack(0, 0, 0, 0),
    extra, state))

# Apply SHA-256 round 57 to the compression state.
def fin57(
  +t0: U32,
  +t1: U32,
  +t2: U32,
  +t3: U32,
  +t4: U32,
  +t5: U32,
  +t6: U32,
  +t7: U32,
  +t8: U32,
  +t9: U32,
  +t10: U32,
  +t11: U32,
  +t12: U32,
  +t13: U32,
  +t14: U32,
  +t15: U32,
  +t16: U32,
  +t17: U32,
  +t18: U32,
  +t19: U32,
  +t20: U32,
  +t21: U32,
  +t22: U32,
  +t23: U32,
  +t24: U32,
  +t25: U32,
  +t26: U32,
  +t27: U32,
  +t28: U32,
  +t29: U32,
  +t30: U32,
  +t31: U32,
  +t32: U32,
  +t33: U32,
  +t34: U32,
  +t35: U32,
  +t36: U32,
  +t37: U32,
  +t38: U32,
  +t39: U32,
  +t40: U32,
  +t41: U32,
  +t42: U32,
  +t43: U32,
  +t44: U32,
  +t45: U32,
  +t46: U32,
  +t47: U32,
  +t48: U32,
  +t49: U32,
  +t50: U32,
  +t51: U32,
  +t52: U32,
  +t53: U32,
  +t54: U32,
  +t55: U32,
  +t56: U32,
  +byte_length: Nat,
  +extra: Nat,
  state: S.State
) -> S.State:
  fips_compress16(pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), len_hi(byte_length), len_lo(byte_length),
    extra, fips_compress16(pack(t0, t1, t2, t3), pack(t4, t5, t6, t7), pack(t8, t9, t10, t11), pack(t12, t13, t14, t15), pack(t16, t17, t18, t19), pack(t20, t21, t22, t23), pack(t24, t25, t26, t27), pack(t28, t29, t30, t31), pack(t32, t33, t34, t35), pack(t36, t37, t38, t39), pack(t40, t41, t42, t43), pack(t44, t45, t46, t47), pack(t48, t49, t50, t51), pack(t52, t53, t54, t55), pack(t56, 128, 0, 0), pack(0, 0, 0, 0),
    extra, state))

# Apply SHA-256 round 58 to the compression state.
def fin58(
  +t0: U32,
  +t1: U32,
  +t2: U32,
  +t3: U32,
  +t4: U32,
  +t5: U32,
  +t6: U32,
  +t7: U32,
  +t8: U32,
  +t9: U32,
  +t10: U32,
  +t11: U32,
  +t12: U32,
  +t13: U32,
  +t14: U32,
  +t15: U32,
  +t16: U32,
  +t17: U32,
  +t18: U32,
  +t19: U32,
  +t20: U32,
  +t21: U32,
  +t22: U32,
  +t23: U32,
  +t24: U32,
  +t25: U32,
  +t26: U32,
  +t27: U32,
  +t28: U32,
  +t29: U32,
  +t30: U32,
  +t31: U32,
  +t32: U32,
  +t33: U32,
  +t34: U32,
  +t35: U32,
  +t36: U32,
  +t37: U32,
  +t38: U32,
  +t39: U32,
  +t40: U32,
  +t41: U32,
  +t42: U32,
  +t43: U32,
  +t44: U32,
  +t45: U32,
  +t46: U32,
  +t47: U32,
  +t48: U32,
  +t49: U32,
  +t50: U32,
  +t51: U32,
  +t52: U32,
  +t53: U32,
  +t54: U32,
  +t55: U32,
  +t56: U32,
  +t57: U32,
  +byte_length: Nat,
  +extra: Nat,
  state: S.State
) -> S.State:
  fips_compress16(pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), len_hi(byte_length), len_lo(byte_length),
    extra, fips_compress16(pack(t0, t1, t2, t3), pack(t4, t5, t6, t7), pack(t8, t9, t10, t11), pack(t12, t13, t14, t15), pack(t16, t17, t18, t19), pack(t20, t21, t22, t23), pack(t24, t25, t26, t27), pack(t28, t29, t30, t31), pack(t32, t33, t34, t35), pack(t36, t37, t38, t39), pack(t40, t41, t42, t43), pack(t44, t45, t46, t47), pack(t48, t49, t50, t51), pack(t52, t53, t54, t55), pack(t56, t57, 128, 0), pack(0, 0, 0, 0),
    extra, state))

# Apply SHA-256 round 59 to the compression state.
def fin59(
  +t0: U32,
  +t1: U32,
  +t2: U32,
  +t3: U32,
  +t4: U32,
  +t5: U32,
  +t6: U32,
  +t7: U32,
  +t8: U32,
  +t9: U32,
  +t10: U32,
  +t11: U32,
  +t12: U32,
  +t13: U32,
  +t14: U32,
  +t15: U32,
  +t16: U32,
  +t17: U32,
  +t18: U32,
  +t19: U32,
  +t20: U32,
  +t21: U32,
  +t22: U32,
  +t23: U32,
  +t24: U32,
  +t25: U32,
  +t26: U32,
  +t27: U32,
  +t28: U32,
  +t29: U32,
  +t30: U32,
  +t31: U32,
  +t32: U32,
  +t33: U32,
  +t34: U32,
  +t35: U32,
  +t36: U32,
  +t37: U32,
  +t38: U32,
  +t39: U32,
  +t40: U32,
  +t41: U32,
  +t42: U32,
  +t43: U32,
  +t44: U32,
  +t45: U32,
  +t46: U32,
  +t47: U32,
  +t48: U32,
  +t49: U32,
  +t50: U32,
  +t51: U32,
  +t52: U32,
  +t53: U32,
  +t54: U32,
  +t55: U32,
  +t56: U32,
  +t57: U32,
  +t58: U32,
  +byte_length: Nat,
  +extra: Nat,
  state: S.State
) -> S.State:
  fips_compress16(pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), len_hi(byte_length), len_lo(byte_length),
    extra, fips_compress16(pack(t0, t1, t2, t3), pack(t4, t5, t6, t7), pack(t8, t9, t10, t11), pack(t12, t13, t14, t15), pack(t16, t17, t18, t19), pack(t20, t21, t22, t23), pack(t24, t25, t26, t27), pack(t28, t29, t30, t31), pack(t32, t33, t34, t35), pack(t36, t37, t38, t39), pack(t40, t41, t42, t43), pack(t44, t45, t46, t47), pack(t48, t49, t50, t51), pack(t52, t53, t54, t55), pack(t56, t57, t58, 128), pack(0, 0, 0, 0),
    extra, state))

# Apply SHA-256 round 60 to the compression state.
def fin60(
  +t0: U32,
  +t1: U32,
  +t2: U32,
  +t3: U32,
  +t4: U32,
  +t5: U32,
  +t6: U32,
  +t7: U32,
  +t8: U32,
  +t9: U32,
  +t10: U32,
  +t11: U32,
  +t12: U32,
  +t13: U32,
  +t14: U32,
  +t15: U32,
  +t16: U32,
  +t17: U32,
  +t18: U32,
  +t19: U32,
  +t20: U32,
  +t21: U32,
  +t22: U32,
  +t23: U32,
  +t24: U32,
  +t25: U32,
  +t26: U32,
  +t27: U32,
  +t28: U32,
  +t29: U32,
  +t30: U32,
  +t31: U32,
  +t32: U32,
  +t33: U32,
  +t34: U32,
  +t35: U32,
  +t36: U32,
  +t37: U32,
  +t38: U32,
  +t39: U32,
  +t40: U32,
  +t41: U32,
  +t42: U32,
  +t43: U32,
  +t44: U32,
  +t45: U32,
  +t46: U32,
  +t47: U32,
  +t48: U32,
  +t49: U32,
  +t50: U32,
  +t51: U32,
  +t52: U32,
  +t53: U32,
  +t54: U32,
  +t55: U32,
  +t56: U32,
  +t57: U32,
  +t58: U32,
  +t59: U32,
  +byte_length: Nat,
  +extra: Nat,
  state: S.State
) -> S.State:
  fips_compress16(pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), len_hi(byte_length), len_lo(byte_length),
    extra, fips_compress16(pack(t0, t1, t2, t3), pack(t4, t5, t6, t7), pack(t8, t9, t10, t11), pack(t12, t13, t14, t15), pack(t16, t17, t18, t19), pack(t20, t21, t22, t23), pack(t24, t25, t26, t27), pack(t28, t29, t30, t31), pack(t32, t33, t34, t35), pack(t36, t37, t38, t39), pack(t40, t41, t42, t43), pack(t44, t45, t46, t47), pack(t48, t49, t50, t51), pack(t52, t53, t54, t55), pack(t56, t57, t58, t59), pack(128, 0, 0, 0),
    extra, state))

# Apply SHA-256 round 61 to the compression state.
def fin61(
  +t0: U32,
  +t1: U32,
  +t2: U32,
  +t3: U32,
  +t4: U32,
  +t5: U32,
  +t6: U32,
  +t7: U32,
  +t8: U32,
  +t9: U32,
  +t10: U32,
  +t11: U32,
  +t12: U32,
  +t13: U32,
  +t14: U32,
  +t15: U32,
  +t16: U32,
  +t17: U32,
  +t18: U32,
  +t19: U32,
  +t20: U32,
  +t21: U32,
  +t22: U32,
  +t23: U32,
  +t24: U32,
  +t25: U32,
  +t26: U32,
  +t27: U32,
  +t28: U32,
  +t29: U32,
  +t30: U32,
  +t31: U32,
  +t32: U32,
  +t33: U32,
  +t34: U32,
  +t35: U32,
  +t36: U32,
  +t37: U32,
  +t38: U32,
  +t39: U32,
  +t40: U32,
  +t41: U32,
  +t42: U32,
  +t43: U32,
  +t44: U32,
  +t45: U32,
  +t46: U32,
  +t47: U32,
  +t48: U32,
  +t49: U32,
  +t50: U32,
  +t51: U32,
  +t52: U32,
  +t53: U32,
  +t54: U32,
  +t55: U32,
  +t56: U32,
  +t57: U32,
  +t58: U32,
  +t59: U32,
  +t60: U32,
  +byte_length: Nat,
  +extra: Nat,
  state: S.State
) -> S.State:
  fips_compress16(pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), len_hi(byte_length), len_lo(byte_length),
    extra, fips_compress16(pack(t0, t1, t2, t3), pack(t4, t5, t6, t7), pack(t8, t9, t10, t11), pack(t12, t13, t14, t15), pack(t16, t17, t18, t19), pack(t20, t21, t22, t23), pack(t24, t25, t26, t27), pack(t28, t29, t30, t31), pack(t32, t33, t34, t35), pack(t36, t37, t38, t39), pack(t40, t41, t42, t43), pack(t44, t45, t46, t47), pack(t48, t49, t50, t51), pack(t52, t53, t54, t55), pack(t56, t57, t58, t59), pack(t60, 128, 0, 0),
    extra, state))

# Apply SHA-256 round 62 to the compression state.
def fin62(
  +t0: U32,
  +t1: U32,
  +t2: U32,
  +t3: U32,
  +t4: U32,
  +t5: U32,
  +t6: U32,
  +t7: U32,
  +t8: U32,
  +t9: U32,
  +t10: U32,
  +t11: U32,
  +t12: U32,
  +t13: U32,
  +t14: U32,
  +t15: U32,
  +t16: U32,
  +t17: U32,
  +t18: U32,
  +t19: U32,
  +t20: U32,
  +t21: U32,
  +t22: U32,
  +t23: U32,
  +t24: U32,
  +t25: U32,
  +t26: U32,
  +t27: U32,
  +t28: U32,
  +t29: U32,
  +t30: U32,
  +t31: U32,
  +t32: U32,
  +t33: U32,
  +t34: U32,
  +t35: U32,
  +t36: U32,
  +t37: U32,
  +t38: U32,
  +t39: U32,
  +t40: U32,
  +t41: U32,
  +t42: U32,
  +t43: U32,
  +t44: U32,
  +t45: U32,
  +t46: U32,
  +t47: U32,
  +t48: U32,
  +t49: U32,
  +t50: U32,
  +t51: U32,
  +t52: U32,
  +t53: U32,
  +t54: U32,
  +t55: U32,
  +t56: U32,
  +t57: U32,
  +t58: U32,
  +t59: U32,
  +t60: U32,
  +t61: U32,
  +byte_length: Nat,
  +extra: Nat,
  state: S.State
) -> S.State:
  fips_compress16(pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), len_hi(byte_length), len_lo(byte_length),
    extra, fips_compress16(pack(t0, t1, t2, t3), pack(t4, t5, t6, t7), pack(t8, t9, t10, t11), pack(t12, t13, t14, t15), pack(t16, t17, t18, t19), pack(t20, t21, t22, t23), pack(t24, t25, t26, t27), pack(t28, t29, t30, t31), pack(t32, t33, t34, t35), pack(t36, t37, t38, t39), pack(t40, t41, t42, t43), pack(t44, t45, t46, t47), pack(t48, t49, t50, t51), pack(t52, t53, t54, t55), pack(t56, t57, t58, t59), pack(t60, t61, 128, 0),
    extra, state))

# Apply SHA-256 round 63 to the compression state.
def fin63(
  +t0: U32,
  +t1: U32,
  +t2: U32,
  +t3: U32,
  +t4: U32,
  +t5: U32,
  +t6: U32,
  +t7: U32,
  +t8: U32,
  +t9: U32,
  +t10: U32,
  +t11: U32,
  +t12: U32,
  +t13: U32,
  +t14: U32,
  +t15: U32,
  +t16: U32,
  +t17: U32,
  +t18: U32,
  +t19: U32,
  +t20: U32,
  +t21: U32,
  +t22: U32,
  +t23: U32,
  +t24: U32,
  +t25: U32,
  +t26: U32,
  +t27: U32,
  +t28: U32,
  +t29: U32,
  +t30: U32,
  +t31: U32,
  +t32: U32,
  +t33: U32,
  +t34: U32,
  +t35: U32,
  +t36: U32,
  +t37: U32,
  +t38: U32,
  +t39: U32,
  +t40: U32,
  +t41: U32,
  +t42: U32,
  +t43: U32,
  +t44: U32,
  +t45: U32,
  +t46: U32,
  +t47: U32,
  +t48: U32,
  +t49: U32,
  +t50: U32,
  +t51: U32,
  +t52: U32,
  +t53: U32,
  +t54: U32,
  +t55: U32,
  +t56: U32,
  +t57: U32,
  +t58: U32,
  +t59: U32,
  +t60: U32,
  +t61: U32,
  +t62: U32,
  +byte_length: Nat,
  +extra: Nat,
  state: S.State
) -> S.State:
  fips_compress16(pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), pack(0, 0, 0, 0), len_hi(byte_length), len_lo(byte_length),
    extra, fips_compress16(pack(t0, t1, t2, t3), pack(t4, t5, t6, t7), pack(t8, t9, t10, t11), pack(t12, t13, t14, t15), pack(t16, t17, t18, t19), pack(t20, t21, t22, t23), pack(t24, t25, t26, t27), pack(t28, t29, t30, t31), pack(t32, t33, t34, t35), pack(t36, t37, t38, t39), pack(t40, t41, t42, t43), pack(t44, t45, t46, t47), pack(t48, t49, t50, t51), pack(t52, t53, t54, t55), pack(t56, t57, t58, t59), pack(t60, t61, t62, 128),
    extra, state))

# Tail-recursive block loop over an already padded byte list.
def fips_blocks(bytes: List<&2, U32>, +extra: Nat, state: S.State) -> S.State:
  match bytes:
    case b0 <> b1 <> b2 <> b3 <> b4 <> b5 <> b6 <> b7 <> b8 <> b9 <> b10 <> b11 <> b12 <> b13 <> b14 <> b15 <> b16 <> b17 <> b18 <> b19 <> b20 <> b21 <> b22 <> b23 <> b24 <> b25 <> b26 <> b27 <> b28 <> b29 <> b30 <> b31 <> b32 <> b33 <> b34 <> b35 <> b36 <> b37 <> b38 <> b39 <> b40 <> b41 <> b42 <> b43 <> b44 <> b45 <> b46 <> b47 <> b48 <> b49 <> b50 <> b51 <> b52 <> b53 <> b54 <> b55 <> b56 <> b57 <> b58 <> b59 <> b60 <> b61 <> b62 <> b63 <> rest:
      fips_blocks(rest, extra, fips_compress16(pack(b0, b1, b2, b3), pack(b4, b5, b6, b7), pack(b8, b9, b10, b11), pack(b12, b13, b14, b15), pack(b16, b17, b18, b19), pack(b20, b21, b22, b23), pack(b24, b25, b26, b27), pack(b28, b29, b30, b31), pack(b32, b33, b34, b35), pack(b36, b37, b38, b39), pack(b40, b41, b42, b43), pack(b44, b45, b46, b47), pack(b48, b49, b50, b51), pack(b52, b53, b54, b55), pack(b56, b57, b58, b59), pack(b60, b61, b62, b63), extra, state))
    case _:
      state

# Append zero padding to onto for the SHA-256 compression implementation.
def zeros_onto(word_z: Nat, acc: List<&2, U32>) -> List<&2, U32>:
  match word_z:
    case 0n:
      acc
    case 1n+p:
      zeros_onto(p, 0 <> acc)

# The padding suffix built only with tail-recursive loops.
def padding(+byte_length: Nat) -> List<&2, U32>:
  128 <> zeros_onto(Nat.mod(Nat.sub(119n, Nat.mod(byte_length, 64n)), 64n), bit_length(byte_length))

# Handle byte lengths for count for the SHA-256 compression implementation.
def byte_count(bytes: List<&2, U32>, acc: Nat) -> Nat:
  match bytes:
    case Nil{}:
      acc
    case h <> t:
      byte_count(t, 1n+acc)

# Final block(s) of an n-byte message whose tail has fewer than 64 bytes.
# stream never passes 64 or more bytes; that case pads with tail-recursive
# loops. The match is exhaustive: a default case would make Bend rebuild the
# consumed cells at every depth. Length words are computed directly from n; note
# that sharing any List<U32> would make Bend reference-count every list match,
# including the input loop in stream.
def finish_n(+tail: List<&2, U32>, +byte_length: Nat, +extra: Nat, state: S.State) -> S.State:
  match tail:
    case Nil{}:
      fin0(byte_length, extra, state)
    case t0 <> Nil{}:
      fin1(t0, byte_length, extra, state)
    case t0 <> t1 <> Nil{}:
      fin2(t0, t1, byte_length, extra, state)
    case t0 <> t1 <> t2 <> Nil{}:
      fin3(t0, t1, t2, byte_length, extra, state)
    case t0 <> t1 <> t2 <> t3 <> Nil{}:
      fin4(t0, t1, t2, t3, byte_length, extra, state)
    case t0 <> t1 <> t2 <> t3 <> t4 <> Nil{}:
      fin5(t0, t1, t2, t3, t4, byte_length, extra, state)
    case t0 <> t1 <> t2 <> t3 <> t4 <> t5 <> Nil{}:
      fin6(t0, t1, t2, t3, t4, t5, byte_length, extra, state)
    case t0 <> t1 <> t2 <> t3 <> t4 <> t5 <> t6 <> Nil{}:
      fin7(t0, t1, t2, t3, t4, t5, t6, byte_length, extra, state)
    case t0 <> t1 <> t2 <> t3 <> t4 <> t5 <> t6 <> t7 <> Nil{}:
      fin8(t0, t1, t2, t3, t4, t5, t6, t7, byte_length, extra, state)
    case t0 <> t1 <> t2 <> t3 <> t4 <> t5 <> t6 <> t7 <> t8 <> Nil{}:
      fin9(t0, t1, t2, t3, t4, t5, t6, t7, t8, byte_length, extra, state)
    case t0 <> t1 <> t2 <> t3 <> t4 <> t5 <> t6 <> t7 <> t8 <> t9 <> Nil{}:
      fin10(t0, t1, t2, t3, t4, t5, t6, t7, t8, t9, byte_length, extra, state)
    case t0 <> t1 <> t2 <> t3 <> t4 <> t5 <> t6 <> t7 <> t8 <> t9 <> t10 <> Nil{}:
      fin11(t0, t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, byte_length, extra, state)
    case t0 <> t1 <> t2 <> t3 <> t4 <> t5 <> t6 <> t7 <> t8 <> t9 <> t10 <> t11 <> Nil{}:
      fin12(t0, t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11, byte_length, extra, state)
    case t0 <> t1 <> t2 <> t3 <> t4 <> t5 <> t6 <> t7 <> t8 <> t9 <> t10 <> t11 <> t12 <> Nil{}:
      fin13(t0, t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11, t12, byte_length, extra, state)
    case t0 <> t1 <> t2 <> t3 <> t4 <> t5 <> t6 <> t7 <> t8 <> t9 <> t10 <> t11 <> t12 <> t13 <> Nil{}:
      fin14(t0, t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, byte_length, extra, state)
    case t0 <> t1 <> t2 <> t3 <> t4 <> t5 <> t6 <> t7 <> t8 <> t9 <> t10 <> t11 <> t12 <> t13 <> t14 <> Nil{}:
      fin15(t0, t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, byte_length, extra, state)
    case t0 <> t1 <> t2 <> t3 <> t4 <> t5 <> t6 <> t7 <> t8 <> t9 <> t10 <> t11 <> t12 <> t13 <> t14 <> t15 <> Nil{}:
      fin16(t0, t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, byte_length, extra, state)
    case t0 <> t1 <> t2 <> t3 <> t4 <> t5 <> t6 <> t7 <> t8 <> t9 <> t10 <> t11 <> t12 <> t13 <> t14 <> t15 <> t16 <> Nil{}:
      fin17(t0, t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, byte_length, extra, state)
    case t0 <> t1 <> t2 <> t3 <> t4 <> t5 <> t6 <> t7 <> t8 <> t9 <> t10 <> t11 <> t12 <> t13 <> t14 <> t15 <> t16 <> t17 <> Nil{}:
      fin18(t0, t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, byte_length, extra, state)
    case t0 <> t1 <> t2 <> t3 <> t4 <> t5 <> t6 <> t7 <> t8 <> t9 <> t10 <> t11 <> t12 <> t13 <> t14 <> t15 <> t16 <> t17 <> t18 <> Nil{}:
      fin19(t0, t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, byte_length, extra, state)
    case t0 <> t1 <> t2 <> t3 <> t4 <> t5 <> t6 <> t7 <> t8 <> t9 <> t10 <> t11 <> t12 <> t13 <> t14 <> t15 <> t16 <> t17 <> t18 <> t19 <> Nil{}:
      fin20(t0, t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t19, byte_length, extra, state)
    case t0 <> t1 <> t2 <> t3 <> t4 <> t5 <> t6 <> t7 <> t8 <> t9 <> t10 <> t11 <> t12 <> t13 <> t14 <> t15 <> t16 <> t17 <> t18 <> t19 <> t20 <> Nil{}:
      fin21(t0, t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t19, t20, byte_length, extra, state)
    case t0 <> t1 <> t2 <> t3 <> t4 <> t5 <> t6 <> t7 <> t8 <> t9 <> t10 <> t11 <> t12 <> t13 <> t14 <> t15 <> t16 <> t17 <> t18 <> t19 <> t20 <> t21 <> Nil{}:
      fin22(t0, t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t19, t20, t21, byte_length, extra, state)
    case t0 <> t1 <> t2 <> t3 <> t4 <> t5 <> t6 <> t7 <> t8 <> t9 <> t10 <> t11 <> t12 <> t13 <> t14 <> t15 <> t16 <> t17 <> t18 <> t19 <> t20 <> t21 <> t22 <> Nil{}:
      fin23(t0, t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t19, t20, t21, t22, byte_length, extra, state)
    case t0 <> t1 <> t2 <> t3 <> t4 <> t5 <> t6 <> t7 <> t8 <> t9 <> t10 <> t11 <> t12 <> t13 <> t14 <> t15 <> t16 <> t17 <> t18 <> t19 <> t20 <> t21 <> t22 <> t23 <> Nil{}:
      fin24(t0, t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t19, t20, t21, t22, t23, byte_length, extra, state)
    case t0 <> t1 <> t2 <> t3 <> t4 <> t5 <> t6 <> t7 <> t8 <> t9 <> t10 <> t11 <> t12 <> t13 <> t14 <> t15 <> t16 <> t17 <> t18 <> t19 <> t20 <> t21 <> t22 <> t23 <> t24 <> Nil{}:
      fin25(t0, t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t19, t20, t21, t22, t23, t24, byte_length, extra, state)
    case t0 <> t1 <> t2 <> t3 <> t4 <> t5 <> t6 <> t7 <> t8 <> t9 <> t10 <> t11 <> t12 <> t13 <> t14 <> t15 <> t16 <> t17 <> t18 <> t19 <> t20 <> t21 <> t22 <> t23 <> t24 <> t25 <> Nil{}:
      fin26(t0, t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t19, t20, t21, t22, t23, t24, t25, byte_length, extra, state)
    case t0 <> t1 <> t2 <> t3 <> t4 <> t5 <> t6 <> t7 <> t8 <> t9 <> t10 <> t11 <> t12 <> t13 <> t14 <> t15 <> t16 <> t17 <> t18 <> t19 <> t20 <> t21 <> t22 <> t23 <> t24 <> t25 <> t26 <> Nil{}:
      fin27(t0, t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t19, t20, t21, t22, t23, t24, t25, t26, byte_length, extra, state)
    case t0 <> t1 <> t2 <> t3 <> t4 <> t5 <> t6 <> t7 <> t8 <> t9 <> t10 <> t11 <> t12 <> t13 <> t14 <> t15 <> t16 <> t17 <> t18 <> t19 <> t20 <> t21 <> t22 <> t23 <> t24 <> t25 <> t26 <> t27 <> Nil{}:
      fin28(t0, t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t19, t20, t21, t22, t23, t24, t25, t26, t27, byte_length, extra, state)
    case t0 <> t1 <> t2 <> t3 <> t4 <> t5 <> t6 <> t7 <> t8 <> t9 <> t10 <> t11 <> t12 <> t13 <> t14 <> t15 <> t16 <> t17 <> t18 <> t19 <> t20 <> t21 <> t22 <> t23 <> t24 <> t25 <> t26 <> t27 <> t28 <> Nil{}:
      fin29(t0, t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t19, t20, t21, t22, t23, t24, t25, t26, t27, t28, byte_length, extra, state)
    case t0 <> t1 <> t2 <> t3 <> t4 <> t5 <> t6 <> t7 <> t8 <> t9 <> t10 <> t11 <> t12 <> t13 <> t14 <> t15 <> t16 <> t17 <> t18 <> t19 <> t20 <> t21 <> t22 <> t23 <> t24 <> t25 <> t26 <> t27 <> t28 <> t29 <> Nil{}:
      fin30(t0, t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t19, t20, t21, t22, t23, t24, t25, t26, t27, t28, t29, byte_length, extra, state)
    case t0 <> t1 <> t2 <> t3 <> t4 <> t5 <> t6 <> t7 <> t8 <> t9 <> t10 <> t11 <> t12 <> t13 <> t14 <> t15 <> t16 <> t17 <> t18 <> t19 <> t20 <> t21 <> t22 <> t23 <> t24 <> t25 <> t26 <> t27 <> t28 <> t29 <> t30 <> Nil{}:
      fin31(t0, t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t19, t20, t21, t22, t23, t24, t25, t26, t27, t28, t29, t30, byte_length, extra, state)
    case t0 <> t1 <> t2 <> t3 <> t4 <> t5 <> t6 <> t7 <> t8 <> t9 <> t10 <> t11 <> t12 <> t13 <> t14 <> t15 <> t16 <> t17 <> t18 <> t19 <> t20 <> t21 <> t22 <> t23 <> t24 <> t25 <> t26 <> t27 <> t28 <> t29 <> t30 <> t31 <> Nil{}:
      fin32(t0, t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t19, t20, t21, t22, t23, t24, t25, t26, t27, t28, t29, t30, t31, byte_length, extra, state)
    case t0 <> t1 <> t2 <> t3 <> t4 <> t5 <> t6 <> t7 <> t8 <> t9 <> t10 <> t11 <> t12 <> t13 <> t14 <> t15 <> t16 <> t17 <> t18 <> t19 <> t20 <> t21 <> t22 <> t23 <> t24 <> t25 <> t26 <> t27 <> t28 <> t29 <> t30 <> t31 <> t32 <> Nil{}:
      fin33(t0, t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t19, t20, t21, t22, t23, t24, t25, t26, t27, t28, t29, t30, t31, t32, byte_length, extra, state)
    case t0 <> t1 <> t2 <> t3 <> t4 <> t5 <> t6 <> t7 <> t8 <> t9 <> t10 <> t11 <> t12 <> t13 <> t14 <> t15 <> t16 <> t17 <> t18 <> t19 <> t20 <> t21 <> t22 <> t23 <> t24 <> t25 <> t26 <> t27 <> t28 <> t29 <> t30 <> t31 <> t32 <> t33 <> Nil{}:
      fin34(t0, t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t19, t20, t21, t22, t23, t24, t25, t26, t27, t28, t29, t30, t31, t32, t33, byte_length, extra, state)
    case t0 <> t1 <> t2 <> t3 <> t4 <> t5 <> t6 <> t7 <> t8 <> t9 <> t10 <> t11 <> t12 <> t13 <> t14 <> t15 <> t16 <> t17 <> t18 <> t19 <> t20 <> t21 <> t22 <> t23 <> t24 <> t25 <> t26 <> t27 <> t28 <> t29 <> t30 <> t31 <> t32 <> t33 <> t34 <> Nil{}:
      fin35(t0, t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t19, t20, t21, t22, t23, t24, t25, t26, t27, t28, t29, t30, t31, t32, t33, t34, byte_length, extra, state)
    case t0 <> t1 <> t2 <> t3 <> t4 <> t5 <> t6 <> t7 <> t8 <> t9 <> t10 <> t11 <> t12 <> t13 <> t14 <> t15 <> t16 <> t17 <> t18 <> t19 <> t20 <> t21 <> t22 <> t23 <> t24 <> t25 <> t26 <> t27 <> t28 <> t29 <> t30 <> t31 <> t32 <> t33 <> t34 <> t35 <> Nil{}:
      fin36(t0, t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t19, t20, t21, t22, t23, t24, t25, t26, t27, t28, t29, t30, t31, t32, t33, t34, t35, byte_length, extra, state)
    case t0 <> t1 <> t2 <> t3 <> t4 <> t5 <> t6 <> t7 <> t8 <> t9 <> t10 <> t11 <> t12 <> t13 <> t14 <> t15 <> t16 <> t17 <> t18 <> t19 <> t20 <> t21 <> t22 <> t23 <> t24 <> t25 <> t26 <> t27 <> t28 <> t29 <> t30 <> t31 <> t32 <> t33 <> t34 <> t35 <> t36 <> Nil{}:
      fin37(t0, t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t19, t20, t21, t22, t23, t24, t25, t26, t27, t28, t29, t30, t31, t32, t33, t34, t35, t36, byte_length, extra, state)
    case t0 <> t1 <> t2 <> t3 <> t4 <> t5 <> t6 <> t7 <> t8 <> t9 <> t10 <> t11 <> t12 <> t13 <> t14 <> t15 <> t16 <> t17 <> t18 <> t19 <> t20 <> t21 <> t22 <> t23 <> t24 <> t25 <> t26 <> t27 <> t28 <> t29 <> t30 <> t31 <> t32 <> t33 <> t34 <> t35 <> t36 <> t37 <> Nil{}:
      fin38(t0, t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t19, t20, t21, t22, t23, t24, t25, t26, t27, t28, t29, t30, t31, t32, t33, t34, t35, t36, t37, byte_length, extra, state)
    case t0 <> t1 <> t2 <> t3 <> t4 <> t5 <> t6 <> t7 <> t8 <> t9 <> t10 <> t11 <> t12 <> t13 <> t14 <> t15 <> t16 <> t17 <> t18 <> t19 <> t20 <> t21 <> t22 <> t23 <> t24 <> t25 <> t26 <> t27 <> t28 <> t29 <> t30 <> t31 <> t32 <> t33 <> t34 <> t35 <> t36 <> t37 <> t38 <> Nil{}:
      fin39(t0, t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t19, t20, t21, t22, t23, t24, t25, t26, t27, t28, t29, t30, t31, t32, t33, t34, t35, t36, t37, t38, byte_length, extra, state)
    case t0 <> t1 <> t2 <> t3 <> t4 <> t5 <> t6 <> t7 <> t8 <> t9 <> t10 <> t11 <> t12 <> t13 <> t14 <> t15 <> t16 <> t17 <> t18 <> t19 <> t20 <> t21 <> t22 <> t23 <> t24 <> t25 <> t26 <> t27 <> t28 <> t29 <> t30 <> t31 <> t32 <> t33 <> t34 <> t35 <> t36 <> t37 <> t38 <> t39 <> Nil{}:
      fin40(t0, t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t19, t20, t21, t22, t23, t24, t25, t26, t27, t28, t29, t30, t31, t32, t33, t34, t35, t36, t37, t38, t39, byte_length, extra, state)
    case t0 <> t1 <> t2 <> t3 <> t4 <> t5 <> t6 <> t7 <> t8 <> t9 <> t10 <> t11 <> t12 <> t13 <> t14 <> t15 <> t16 <> t17 <> t18 <> t19 <> t20 <> t21 <> t22 <> t23 <> t24 <> t25 <> t26 <> t27 <> t28 <> t29 <> t30 <> t31 <> t32 <> t33 <> t34 <> t35 <> t36 <> t37 <> t38 <> t39 <> t40 <> Nil{}:
      fin41(t0, t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t19, t20, t21, t22, t23, t24, t25, t26, t27, t28, t29, t30, t31, t32, t33, t34, t35, t36, t37, t38, t39, t40, byte_length, extra, state)
    case t0 <> t1 <> t2 <> t3 <> t4 <> t5 <> t6 <> t7 <> t8 <> t9 <> t10 <> t11 <> t12 <> t13 <> t14 <> t15 <> t16 <> t17 <> t18 <> t19 <> t20 <> t21 <> t22 <> t23 <> t24 <> t25 <> t26 <> t27 <> t28 <> t29 <> t30 <> t31 <> t32 <> t33 <> t34 <> t35 <> t36 <> t37 <> t38 <> t39 <> t40 <> t41 <> Nil{}:
      fin42(t0, t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t19, t20, t21, t22, t23, t24, t25, t26, t27, t28, t29, t30, t31, t32, t33, t34, t35, t36, t37, t38, t39, t40, t41, byte_length, extra, state)
    case t0 <> t1 <> t2 <> t3 <> t4 <> t5 <> t6 <> t7 <> t8 <> t9 <> t10 <> t11 <> t12 <> t13 <> t14 <> t15 <> t16 <> t17 <> t18 <> t19 <> t20 <> t21 <> t22 <> t23 <> t24 <> t25 <> t26 <> t27 <> t28 <> t29 <> t30 <> t31 <> t32 <> t33 <> t34 <> t35 <> t36 <> t37 <> t38 <> t39 <> t40 <> t41 <> t42 <> Nil{}:
      fin43(t0, t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t19, t20, t21, t22, t23, t24, t25, t26, t27, t28, t29, t30, t31, t32, t33, t34, t35, t36, t37, t38, t39, t40, t41, t42, byte_length, extra, state)
    case t0 <> t1 <> t2 <> t3 <> t4 <> t5 <> t6 <> t7 <> t8 <> t9 <> t10 <> t11 <> t12 <> t13 <> t14 <> t15 <> t16 <> t17 <> t18 <> t19 <> t20 <> t21 <> t22 <> t23 <> t24 <> t25 <> t26 <> t27 <> t28 <> t29 <> t30 <> t31 <> t32 <> t33 <> t34 <> t35 <> t36 <> t37 <> t38 <> t39 <> t40 <> t41 <> t42 <> t43 <> Nil{}:
      fin44(t0, t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t19, t20, t21, t22, t23, t24, t25, t26, t27, t28, t29, t30, t31, t32, t33, t34, t35, t36, t37, t38, t39, t40, t41, t42, t43, byte_length, extra, state)
    case t0 <> t1 <> t2 <> t3 <> t4 <> t5 <> t6 <> t7 <> t8 <> t9 <> t10 <> t11 <> t12 <> t13 <> t14 <> t15 <> t16 <> t17 <> t18 <> t19 <> t20 <> t21 <> t22 <> t23 <> t24 <> t25 <> t26 <> t27 <> t28 <> t29 <> t30 <> t31 <> t32 <> t33 <> t34 <> t35 <> t36 <> t37 <> t38 <> t39 <> t40 <> t41 <> t42 <> t43 <> t44 <> Nil{}:
      fin45(t0, t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t19, t20, t21, t22, t23, t24, t25, t26, t27, t28, t29, t30, t31, t32, t33, t34, t35, t36, t37, t38, t39, t40, t41, t42, t43, t44, byte_length, extra, state)
    case t0 <> t1 <> t2 <> t3 <> t4 <> t5 <> t6 <> t7 <> t8 <> t9 <> t10 <> t11 <> t12 <> t13 <> t14 <> t15 <> t16 <> t17 <> t18 <> t19 <> t20 <> t21 <> t22 <> t23 <> t24 <> t25 <> t26 <> t27 <> t28 <> t29 <> t30 <> t31 <> t32 <> t33 <> t34 <> t35 <> t36 <> t37 <> t38 <> t39 <> t40 <> t41 <> t42 <> t43 <> t44 <> t45 <> Nil{}:
      fin46(t0, t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t19, t20, t21, t22, t23, t24, t25, t26, t27, t28, t29, t30, t31, t32, t33, t34, t35, t36, t37, t38, t39, t40, t41, t42, t43, t44, t45, byte_length, extra, state)
    case t0 <> t1 <> t2 <> t3 <> t4 <> t5 <> t6 <> t7 <> t8 <> t9 <> t10 <> t11 <> t12 <> t13 <> t14 <> t15 <> t16 <> t17 <> t18 <> t19 <> t20 <> t21 <> t22 <> t23 <> t24 <> t25 <> t26 <> t27 <> t28 <> t29 <> t30 <> t31 <> t32 <> t33 <> t34 <> t35 <> t36 <> t37 <> t38 <> t39 <> t40 <> t41 <> t42 <> t43 <> t44 <> t45 <> t46 <> Nil{}:
      fin47(t0, t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t19, t20, t21, t22, t23, t24, t25, t26, t27, t28, t29, t30, t31, t32, t33, t34, t35, t36, t37, t38, t39, t40, t41, t42, t43, t44, t45, t46, byte_length, extra, state)
    case t0 <> t1 <> t2 <> t3 <> t4 <> t5 <> t6 <> t7 <> t8 <> t9 <> t10 <> t11 <> t12 <> t13 <> t14 <> t15 <> t16 <> t17 <> t18 <> t19 <> t20 <> t21 <> t22 <> t23 <> t24 <> t25 <> t26 <> t27 <> t28 <> t29 <> t30 <> t31 <> t32 <> t33 <> t34 <> t35 <> t36 <> t37 <> t38 <> t39 <> t40 <> t41 <> t42 <> t43 <> t44 <> t45 <> t46 <> t47 <> Nil{}:
      fin48(t0, t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t19, t20, t21, t22, t23, t24, t25, t26, t27, t28, t29, t30, t31, t32, t33, t34, t35, t36, t37, t38, t39, t40, t41, t42, t43, t44, t45, t46, t47, byte_length, extra, state)
    case t0 <> t1 <> t2 <> t3 <> t4 <> t5 <> t6 <> t7 <> t8 <> t9 <> t10 <> t11 <> t12 <> t13 <> t14 <> t15 <> t16 <> t17 <> t18 <> t19 <> t20 <> t21 <> t22 <> t23 <> t24 <> t25 <> t26 <> t27 <> t28 <> t29 <> t30 <> t31 <> t32 <> t33 <> t34 <> t35 <> t36 <> t37 <> t38 <> t39 <> t40 <> t41 <> t42 <> t43 <> t44 <> t45 <> t46 <> t47 <> t48 <> Nil{}:
      fin49(t0, t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t19, t20, t21, t22, t23, t24, t25, t26, t27, t28, t29, t30, t31, t32, t33, t34, t35, t36, t37, t38, t39, t40, t41, t42, t43, t44, t45, t46, t47, t48, byte_length, extra, state)
    case t0 <> t1 <> t2 <> t3 <> t4 <> t5 <> t6 <> t7 <> t8 <> t9 <> t10 <> t11 <> t12 <> t13 <> t14 <> t15 <> t16 <> t17 <> t18 <> t19 <> t20 <> t21 <> t22 <> t23 <> t24 <> t25 <> t26 <> t27 <> t28 <> t29 <> t30 <> t31 <> t32 <> t33 <> t34 <> t35 <> t36 <> t37 <> t38 <> t39 <> t40 <> t41 <> t42 <> t43 <> t44 <> t45 <> t46 <> t47 <> t48 <> t49 <> Nil{}:
      fin50(t0, t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t19, t20, t21, t22, t23, t24, t25, t26, t27, t28, t29, t30, t31, t32, t33, t34, t35, t36, t37, t38, t39, t40, t41, t42, t43, t44, t45, t46, t47, t48, t49, byte_length, extra, state)
    case t0 <> t1 <> t2 <> t3 <> t4 <> t5 <> t6 <> t7 <> t8 <> t9 <> t10 <> t11 <> t12 <> t13 <> t14 <> t15 <> t16 <> t17 <> t18 <> t19 <> t20 <> t21 <> t22 <> t23 <> t24 <> t25 <> t26 <> t27 <> t28 <> t29 <> t30 <> t31 <> t32 <> t33 <> t34 <> t35 <> t36 <> t37 <> t38 <> t39 <> t40 <> t41 <> t42 <> t43 <> t44 <> t45 <> t46 <> t47 <> t48 <> t49 <> t50 <> Nil{}:
      fin51(t0, t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t19, t20, t21, t22, t23, t24, t25, t26, t27, t28, t29, t30, t31, t32, t33, t34, t35, t36, t37, t38, t39, t40, t41, t42, t43, t44, t45, t46, t47, t48, t49, t50, byte_length, extra, state)
    case t0 <> t1 <> t2 <> t3 <> t4 <> t5 <> t6 <> t7 <> t8 <> t9 <> t10 <> t11 <> t12 <> t13 <> t14 <> t15 <> t16 <> t17 <> t18 <> t19 <> t20 <> t21 <> t22 <> t23 <> t24 <> t25 <> t26 <> t27 <> t28 <> t29 <> t30 <> t31 <> t32 <> t33 <> t34 <> t35 <> t36 <> t37 <> t38 <> t39 <> t40 <> t41 <> t42 <> t43 <> t44 <> t45 <> t46 <> t47 <> t48 <> t49 <> t50 <> t51 <> Nil{}:
      fin52(t0, t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t19, t20, t21, t22, t23, t24, t25, t26, t27, t28, t29, t30, t31, t32, t33, t34, t35, t36, t37, t38, t39, t40, t41, t42, t43, t44, t45, t46, t47, t48, t49, t50, t51, byte_length, extra, state)
    case t0 <> t1 <> t2 <> t3 <> t4 <> t5 <> t6 <> t7 <> t8 <> t9 <> t10 <> t11 <> t12 <> t13 <> t14 <> t15 <> t16 <> t17 <> t18 <> t19 <> t20 <> t21 <> t22 <> t23 <> t24 <> t25 <> t26 <> t27 <> t28 <> t29 <> t30 <> t31 <> t32 <> t33 <> t34 <> t35 <> t36 <> t37 <> t38 <> t39 <> t40 <> t41 <> t42 <> t43 <> t44 <> t45 <> t46 <> t47 <> t48 <> t49 <> t50 <> t51 <> t52 <> Nil{}:
      fin53(t0, t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t19, t20, t21, t22, t23, t24, t25, t26, t27, t28, t29, t30, t31, t32, t33, t34, t35, t36, t37, t38, t39, t40, t41, t42, t43, t44, t45, t46, t47, t48, t49, t50, t51, t52, byte_length, extra, state)
    case t0 <> t1 <> t2 <> t3 <> t4 <> t5 <> t6 <> t7 <> t8 <> t9 <> t10 <> t11 <> t12 <> t13 <> t14 <> t15 <> t16 <> t17 <> t18 <> t19 <> t20 <> t21 <> t22 <> t23 <> t24 <> t25 <> t26 <> t27 <> t28 <> t29 <> t30 <> t31 <> t32 <> t33 <> t34 <> t35 <> t36 <> t37 <> t38 <> t39 <> t40 <> t41 <> t42 <> t43 <> t44 <> t45 <> t46 <> t47 <> t48 <> t49 <> t50 <> t51 <> t52 <> t53 <> Nil{}:
      fin54(t0, t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t19, t20, t21, t22, t23, t24, t25, t26, t27, t28, t29, t30, t31, t32, t33, t34, t35, t36, t37, t38, t39, t40, t41, t42, t43, t44, t45, t46, t47, t48, t49, t50, t51, t52, t53, byte_length, extra, state)
    case t0 <> t1 <> t2 <> t3 <> t4 <> t5 <> t6 <> t7 <> t8 <> t9 <> t10 <> t11 <> t12 <> t13 <> t14 <> t15 <> t16 <> t17 <> t18 <> t19 <> t20 <> t21 <> t22 <> t23 <> t24 <> t25 <> t26 <> t27 <> t28 <> t29 <> t30 <> t31 <> t32 <> t33 <> t34 <> t35 <> t36 <> t37 <> t38 <> t39 <> t40 <> t41 <> t42 <> t43 <> t44 <> t45 <> t46 <> t47 <> t48 <> t49 <> t50 <> t51 <> t52 <> t53 <> t54 <> Nil{}:
      fin55(t0, t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t19, t20, t21, t22, t23, t24, t25, t26, t27, t28, t29, t30, t31, t32, t33, t34, t35, t36, t37, t38, t39, t40, t41, t42, t43, t44, t45, t46, t47, t48, t49, t50, t51, t52, t53, t54, byte_length, extra, state)
    case t0 <> t1 <> t2 <> t3 <> t4 <> t5 <> t6 <> t7 <> t8 <> t9 <> t10 <> t11 <> t12 <> t13 <> t14 <> t15 <> t16 <> t17 <> t18 <> t19 <> t20 <> t21 <> t22 <> t23 <> t24 <> t25 <> t26 <> t27 <> t28 <> t29 <> t30 <> t31 <> t32 <> t33 <> t34 <> t35 <> t36 <> t37 <> t38 <> t39 <> t40 <> t41 <> t42 <> t43 <> t44 <> t45 <> t46 <> t47 <> t48 <> t49 <> t50 <> t51 <> t52 <> t53 <> t54 <> t55 <> Nil{}:
      fin56(t0, t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t19, t20, t21, t22, t23, t24, t25, t26, t27, t28, t29, t30, t31, t32, t33, t34, t35, t36, t37, t38, t39, t40, t41, t42, t43, t44, t45, t46, t47, t48, t49, t50, t51, t52, t53, t54, t55, byte_length, extra, state)
    case t0 <> t1 <> t2 <> t3 <> t4 <> t5 <> t6 <> t7 <> t8 <> t9 <> t10 <> t11 <> t12 <> t13 <> t14 <> t15 <> t16 <> t17 <> t18 <> t19 <> t20 <> t21 <> t22 <> t23 <> t24 <> t25 <> t26 <> t27 <> t28 <> t29 <> t30 <> t31 <> t32 <> t33 <> t34 <> t35 <> t36 <> t37 <> t38 <> t39 <> t40 <> t41 <> t42 <> t43 <> t44 <> t45 <> t46 <> t47 <> t48 <> t49 <> t50 <> t51 <> t52 <> t53 <> t54 <> t55 <> t56 <> Nil{}:
      fin57(t0, t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t19, t20, t21, t22, t23, t24, t25, t26, t27, t28, t29, t30, t31, t32, t33, t34, t35, t36, t37, t38, t39, t40, t41, t42, t43, t44, t45, t46, t47, t48, t49, t50, t51, t52, t53, t54, t55, t56, byte_length, extra, state)
    case t0 <> t1 <> t2 <> t3 <> t4 <> t5 <> t6 <> t7 <> t8 <> t9 <> t10 <> t11 <> t12 <> t13 <> t14 <> t15 <> t16 <> t17 <> t18 <> t19 <> t20 <> t21 <> t22 <> t23 <> t24 <> t25 <> t26 <> t27 <> t28 <> t29 <> t30 <> t31 <> t32 <> t33 <> t34 <> t35 <> t36 <> t37 <> t38 <> t39 <> t40 <> t41 <> t42 <> t43 <> t44 <> t45 <> t46 <> t47 <> t48 <> t49 <> t50 <> t51 <> t52 <> t53 <> t54 <> t55 <> t56 <> t57 <> Nil{}:
      fin58(t0, t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t19, t20, t21, t22, t23, t24, t25, t26, t27, t28, t29, t30, t31, t32, t33, t34, t35, t36, t37, t38, t39, t40, t41, t42, t43, t44, t45, t46, t47, t48, t49, t50, t51, t52, t53, t54, t55, t56, t57, byte_length, extra, state)
    case t0 <> t1 <> t2 <> t3 <> t4 <> t5 <> t6 <> t7 <> t8 <> t9 <> t10 <> t11 <> t12 <> t13 <> t14 <> t15 <> t16 <> t17 <> t18 <> t19 <> t20 <> t21 <> t22 <> t23 <> t24 <> t25 <> t26 <> t27 <> t28 <> t29 <> t30 <> t31 <> t32 <> t33 <> t34 <> t35 <> t36 <> t37 <> t38 <> t39 <> t40 <> t41 <> t42 <> t43 <> t44 <> t45 <> t46 <> t47 <> t48 <> t49 <> t50 <> t51 <> t52 <> t53 <> t54 <> t55 <> t56 <> t57 <> t58 <> Nil{}:
      fin59(t0, t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t19, t20, t21, t22, t23, t24, t25, t26, t27, t28, t29, t30, t31, t32, t33, t34, t35, t36, t37, t38, t39, t40, t41, t42, t43, t44, t45, t46, t47, t48, t49, t50, t51, t52, t53, t54, t55, t56, t57, t58, byte_length, extra, state)
    case t0 <> t1 <> t2 <> t3 <> t4 <> t5 <> t6 <> t7 <> t8 <> t9 <> t10 <> t11 <> t12 <> t13 <> t14 <> t15 <> t16 <> t17 <> t18 <> t19 <> t20 <> t21 <> t22 <> t23 <> t24 <> t25 <> t26 <> t27 <> t28 <> t29 <> t30 <> t31 <> t32 <> t33 <> t34 <> t35 <> t36 <> t37 <> t38 <> t39 <> t40 <> t41 <> t42 <> t43 <> t44 <> t45 <> t46 <> t47 <> t48 <> t49 <> t50 <> t51 <> t52 <> t53 <> t54 <> t55 <> t56 <> t57 <> t58 <> t59 <> Nil{}:
      fin60(t0, t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t19, t20, t21, t22, t23, t24, t25, t26, t27, t28, t29, t30, t31, t32, t33, t34, t35, t36, t37, t38, t39, t40, t41, t42, t43, t44, t45, t46, t47, t48, t49, t50, t51, t52, t53, t54, t55, t56, t57, t58, t59, byte_length, extra, state)
    case t0 <> t1 <> t2 <> t3 <> t4 <> t5 <> t6 <> t7 <> t8 <> t9 <> t10 <> t11 <> t12 <> t13 <> t14 <> t15 <> t16 <> t17 <> t18 <> t19 <> t20 <> t21 <> t22 <> t23 <> t24 <> t25 <> t26 <> t27 <> t28 <> t29 <> t30 <> t31 <> t32 <> t33 <> t34 <> t35 <> t36 <> t37 <> t38 <> t39 <> t40 <> t41 <> t42 <> t43 <> t44 <> t45 <> t46 <> t47 <> t48 <> t49 <> t50 <> t51 <> t52 <> t53 <> t54 <> t55 <> t56 <> t57 <> t58 <> t59 <> t60 <> Nil{}:
      fin61(t0, t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t19, t20, t21, t22, t23, t24, t25, t26, t27, t28, t29, t30, t31, t32, t33, t34, t35, t36, t37, t38, t39, t40, t41, t42, t43, t44, t45, t46, t47, t48, t49, t50, t51, t52, t53, t54, t55, t56, t57, t58, t59, t60, byte_length, extra, state)
    case t0 <> t1 <> t2 <> t3 <> t4 <> t5 <> t6 <> t7 <> t8 <> t9 <> t10 <> t11 <> t12 <> t13 <> t14 <> t15 <> t16 <> t17 <> t18 <> t19 <> t20 <> t21 <> t22 <> t23 <> t24 <> t25 <> t26 <> t27 <> t28 <> t29 <> t30 <> t31 <> t32 <> t33 <> t34 <> t35 <> t36 <> t37 <> t38 <> t39 <> t40 <> t41 <> t42 <> t43 <> t44 <> t45 <> t46 <> t47 <> t48 <> t49 <> t50 <> t51 <> t52 <> t53 <> t54 <> t55 <> t56 <> t57 <> t58 <> t59 <> t60 <> t61 <> Nil{}:
      fin62(t0, t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t19, t20, t21, t22, t23, t24, t25, t26, t27, t28, t29, t30, t31, t32, t33, t34, t35, t36, t37, t38, t39, t40, t41, t42, t43, t44, t45, t46, t47, t48, t49, t50, t51, t52, t53, t54, t55, t56, t57, t58, t59, t60, t61, byte_length, extra, state)
    case t0 <> t1 <> t2 <> t3 <> t4 <> t5 <> t6 <> t7 <> t8 <> t9 <> t10 <> t11 <> t12 <> t13 <> t14 <> t15 <> t16 <> t17 <> t18 <> t19 <> t20 <> t21 <> t22 <> t23 <> t24 <> t25 <> t26 <> t27 <> t28 <> t29 <> t30 <> t31 <> t32 <> t33 <> t34 <> t35 <> t36 <> t37 <> t38 <> t39 <> t40 <> t41 <> t42 <> t43 <> t44 <> t45 <> t46 <> t47 <> t48 <> t49 <> t50 <> t51 <> t52 <> t53 <> t54 <> t55 <> t56 <> t57 <> t58 <> t59 <> t60 <> t61 <> t62 <> Nil{}:
      fin63(t0, t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t19, t20, t21, t22, t23, t24, t25, t26, t27, t28, t29, t30, t31, t32, t33, t34, t35, t36, t37, t38, t39, t40, t41, t42, t43, t44, t45, t46, t47, t48, t49, t50, t51, t52, t53, t54, t55, t56, t57, t58, t59, t60, t61, t62, byte_length, extra, state)
    case t0 <> t1 <> t2 <> t3 <> t4 <> t5 <> t6 <> t7 <> t8 <> t9 <> t10 <> t11 <> t12 <> t13 <> t14 <> t15 <> t16 <> t17 <> t18 <> t19 <> t20 <> t21 <> t22 <> t23 <> t24 <> t25 <> t26 <> t27 <> t28 <> t29 <> t30 <> t31 <> t32 <> t33 <> t34 <> t35 <> t36 <> t37 <> t38 <> t39 <> t40 <> t41 <> t42 <> t43 <> t44 <> t45 <> t46 <> t47 <> t48 <> t49 <> t50 <> t51 <> t52 <> t53 <> t54 <> t55 <> t56 <> t57 <> t58 <> t59 <> t60 <> t61 <> t62 <> t63 <> rest:
      fips_blocks(List.reverse.go(&2, U32, List.reverse(&2, U32, t0 <> t1 <> t2 <> t3 <> t4 <> t5 <> t6 <> t7 <> t8 <> t9 <> t10 <> t11 <> t12 <> t13 <> t14 <> t15 <> t16 <> t17 <> t18 <> t19 <> t20 <> t21 <> t22 <> t23 <> t24 <> t25 <> t26 <> t27 <> t28 <> t29 <> t30 <> t31 <> t32 <> t33 <> t34 <> t35 <> t36 <> t37 <> t38 <> t39 <> t40 <> t41 <> t42 <> t43 <> t44 <> t45 <> t46 <> t47 <> t48 <> t49 <> t50 <> t51 <> t52 <> t53 <> t54 <> t55 <> t56 <> t57 <> t58 <> t59 <> t60 <> t61 <> t62 <> t63 <> rest), padding(byte_length)), extra, state)

# count is the number of bytes already hashed, always a multiple of 64.
def finish(+tail: List<&2, U32>, count: Nat, +extra: Nat, state: S.State) -> S.State:
  finish_n(tail, byte_count(tail, count), extra, state)

# Compress complete 64-byte blocks straight from the input list, so the
# message is never copied, counted or reversed. count is the number of bytes
# already hashed and extra the number of derived schedule words (48).
def stream(+bytes: List<&2, U32>, count: Nat, +extra: Nat, state: S.State) -> S.State:
  match bytes:
    case b0 <> b1 <> b2 <> b3 <> b4 <> b5 <> b6 <> b7 <> b8 <> b9 <> b10 <> b11 <> b12 <> b13 <> b14 <> b15 <> b16 <> b17 <> b18 <> b19 <> b20 <> b21 <> b22 <> b23 <> b24 <> b25 <> b26 <> b27 <> b28 <> b29 <> b30 <> b31 <> b32 <> b33 <> b34 <> b35 <> b36 <> b37 <> b38 <> b39 <> b40 <> b41 <> b42 <> b43 <> b44 <> b45 <> b46 <> b47 <> b48 <> b49 <> b50 <> b51 <> b52 <> b53 <> b54 <> b55 <> b56 <> b57 <> b58 <> b59 <> b60 <> b61 <> b62 <> b63 <> rest:
      stream(rest, Nat.add(64n, count), extra, fips_compress16(
        pack(b0, b1, b2, b3), pack(b4, b5, b6, b7), pack(b8, b9, b10, b11), pack(b12, b13, b14, b15),
        pack(b16, b17, b18, b19), pack(b20, b21, b22, b23), pack(b24, b25, b26, b27), pack(b28, b29, b30, b31),
        pack(b32, b33, b34, b35), pack(b36, b37, b38, b39), pack(b40, b41, b42, b43), pack(b44, b45, b46, b47),
        pack(b48, b49, b50, b51), pack(b52, b53, b54, b55), pack(b56, b57, b58, b59), pack(b60, b61, b62, b63),
        extra, state))
    case _:
      finish(bytes, count, extra, state)

# ASCII convenience only; binary inputs use sha256 directly.
def ascii(arg_s: String) -> List<&2, U32>:
  match arg_s:
    case SNil{}:
      Nil{}
    case SCon{Chr{c}, t}:
      c <> ascii(t)

# Decode hexadecimal digit if for the SHA-256 compression implementation.
def hex_digit_if(digit: U32, small: Bool) -> Char:
  match small:
    case True{}:
      Chr{(48 + digit : U32)}
    case False{}:
      Chr{(87 + digit : U32)}

# Decode hexadecimal digit for the SHA-256 compression implementation.
def hex_digit(+digit: U32) -> Char:
  hex_digit_if(digit, U32.is_lt(digit, 10))

# Decode hexadecimal word go for the SHA-256 compression implementation.
def hex_word_go(digit_count: Nat, +word: U32, acc: String) -> String:
  match digit_count:
    case 0n:
      acc
    case 1n+p:
      hex_word_go(p, U32.shrn(word, 4n), SCon{hex_digit((word .&. 15 : U32)), acc})

# Decode hexadecimal word for the SHA-256 compression implementation.
def hex_word(word: U32) -> String:
  hex_word_go(8n, word, "")

# Handle hex in the SHA-256 compression implementation.
def hex(ws: List<&2, U32>) -> String:
  match ws:
    case Nil{}:
      ""
    case w <> t:
      hex_word(w) ++ hex(t)

# Handle sha256 in the SHA-256 compression implementation.
def sha256(bytes: List<&2, U32>) -> List<&2, U32>:
  digest(stream(bytes, 0n, 48n, initial()))
