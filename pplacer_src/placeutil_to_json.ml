open Subcommand
open Guppy_cmdobjs

class cmd () =
object
  inherit subcommand () as super
  inherit placefile_cmd () as super_placefile

  method specl = []

  method desc = "converts .place files to .place.json files."
  method usage = "usage: to_json placefile[s]"

  method private placefile_action prl =
    List.iter
      (fun pr ->
        let out_name = (pr.Placerun.name ^ ".json") in
        Placerun_io.to_json_file
          "guppy to_json"
          out_name
          pr)
      prl
end
