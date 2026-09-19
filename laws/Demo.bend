import Base
import ../app/demo_helpers.bend as Demo

# --- Demo worker (CLI/demo plan) ---
law demo_worker_zero:
  {Demo.worker(0n, 0n) == 0n : Nat}

law demo_worker_gpu_agrees:
  {Demo.worker_gpu(8n, 0n) == Demo.worker(8n, 0n) : Nat}
