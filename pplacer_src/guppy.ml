let () =
  Subcommand.inner_loop
    ~prg_name:"guppy"
    ~version:Version.version_revision
    (Subcommand.cmd_map_of_list (Guppy_commands.command_list ()))
