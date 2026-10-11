import Base
import ../src/coordinator/SpawnPolicy.bend as Spawn

# Keeps a space-containing argument intact and in its supplied position.
law spawn_arguments_are_preserved_without_shell_parsing:
  {Spawn.prepare("/bin/owner", Con{"--db path with spaces", Con{"; touch marker", Nil{}}}) ==
    Spawn.SpawnReady{Con{"/bin/owner", Con{"--db path with spaces", Con{"; touch marker", Nil{}}}}} :
    Spawn.Decision}

# Rejects an empty executable before the host process operation.
law empty_spawn_program_is_rejected:
  {Spawn.prepare("", Nil{}) == Spawn.SpawnInvalid{} : Spawn.Decision}

# Rejects an executable containing NUL before C-string conversion.
law nul_spawn_program_is_rejected:
  {Spawn.prepare(SCon{Chr{0}, SNil{}}, Nil{}) == Spawn.SpawnInvalid{} : Spawn.Decision}

# Rejects an argument containing NUL before process launch.
law nul_spawn_argument_is_rejected:
  {Spawn.prepare("/bin/owner", Con{SCon{Chr{0}, SNil{}}, Nil{}}) ==
    Spawn.SpawnInvalid{} : Spawn.Decision}
