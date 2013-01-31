(* OCaml-C interface to lcfit_tripod *)

open Ppatteries

module BA = Bigarray
module BA1 = Bigarray.Array1

exception Lcfit_err of (int * string)
let _ = Callback.register_exception "lcfit_err" (Lcfit_err (0, "any string"))

(* distal branch length, pendant branch length, log-likelihood *)
type tripod_point = (float * float * float)

(* The binary symmetric model for a tripod, with one branch length fixed *)
type tripod_bsm = {n00: float; n01: float; n10: float; n11: float;
                   r:   float; b:   float; t:   float; rx:  float;
                   bx:  float}

(* Evaluate the log-likelihood of the BSM given dist_bl, pend_bl, and the model *)
external log_like: tripod_bsm -> float -> float -> float = "caml_lcfit_tripod_ll"

(* Evaluate the jacobian of the BSM given dist_bl, pend_bl, and the model *)
external jacobian: tripod_bsm -> float -> float -> float array = "caml_lcfit_tripod_jacobian"

(* Fit the BSM given vectors of (dist_bl, pend_bl, log_like) and an initial estimate of the
   model *)
external fit: tripod_bsm -> tripod_point array -> tripod_bsm = "caml_lcfit_tripod_fit"

external est_rx: tripod_bsm -> tripod_point -> float = "caml_lcfit_tripod_est_rx"

(* Rescale m to intersect with (dist_bl, pend_bl, ll) *)
let rescale (dist_bl, pend_bl, ll) m =
  let est_ll = log_like m dist_bl pend_bl in
  let fac = ll /. est_ll in
  {m with n00=m.n00 *. fac;
          n01=m.n01 *. fac;
          n10=m.n10 *. fac;
          n11=m.n11 *. fac}

(* Attempt to get rx on the correct order of magnitude for
 * (dist_bl, pend_bl, ll) *)
let rescale_rx (dist_bl, pend_bl, ll) m =
  let rec aux m =
    let fit_ll = log_like m dist_bl pend_bl in
    let m' =
      if fit_ll < ll then {m with rx=m.rx *. 0.1}
      else {m with rx=m.rx /. 10.}
    in
      if Float.abs (ll -. (log_like m' dist_bl pend_bl)) < Float.abs (ll -. fit_ll)
      then aux m'
      else m
  in
  aux m

(* This seems to provide sensible defaults *)
let default_model t =
  {n00=1500.;n01=300.;n10=300.;n11=300.;r=1.;b=0.5;t=t;rx=1.;bx=0.5}

(* Evaluate log_like' at the cartesian product of points sampled uniformly
 * between [0,cut_bl] and [0,max_pend], fit the tripod_bsm using `keep_top` of
 * these points *)
let find_points_fit_model ?(n_dist=10) ?(n_pend=10) ?(keep_top=50) cut_bl max_pend log_like' =
  let evenly_spaced n min max =
    let d = max -. min
    and nf = (Float.of_int n) -. 1.0
    in
    assert(d > 0.);
    0 -- (n - 1)
    |> map Float.of_int
    |> map (fun i -> min +. (d *. i) /. nf)
    |> List.of_enum
  in
  let dist_bls = if cut_bl =~ 0.  then [cut_bl] else evenly_spaced n_dist 1e-6 (cut_bl -. 1e-6)
  and pend_bls = evenly_spaced n_pend 1e-6 max_pend
  in
  let pts = List.cartesian_product dist_bls pend_bls
    |> List.map (fun (dist_bl, pend_bl) ->
        (dist_bl, pend_bl, (log_like' dist_bl pend_bl)))
    |> List.sort (fun (_,_,a) (_,_,b) -> Float.compare b a)
  in
  let max_ll = List.hd pts in
  let init_model = default_model cut_bl |> rescale max_ll in
  (* See which direction to move rx *)
  let pend_pt = pts
    |> List.enum
    |> Enum.filter (fun (d,p,l) -> d =~ (Tuple3.first max_ll) && p =~ max_pend)
    |> Enum.get
    |> Option.get
  in
  let m =
    if (Tuple3.third max_ll) > (Tuple3.third pend_pt) then
      {init_model with rx=1e-5}
    else
      rescale_rx pend_pt init_model
  in
  let rec choose_rx_fit m pts rxs =
    match rxs with
    | rx :: tail ->
      try
        fit
          {m with rx=rx}
          pts
      with
      | Lcfit_err(c, s) ->
        match tail with
        | [] -> raise (Lcfit_err (c, s))
        | _ -> choose_rx_fit m pts tail
        | _ -> failwith "No rxs"
  in
  choose_rx_fit
    m
    (pts |> List.enum |> Enum.take keep_top |> Array.of_enum)
    [1e-5; 1e-4; 1e-3; 1e-2; 1e-1; 1e0; 1e1;]

let calc_marg_prob model cut_bl prior base_ll upper_limit =
  (* Select some points to sample - uniformly from 0-cut_bl, 0-max_pend *)
  let max_n_exceptions = 10
  and n_exceptions = ref 0
  and ll = log_like model
  and abs_err = 0.
  and rel_err = 1e-2
  in
  let rec perform upper_limit =
    if !n_exceptions >= max_n_exceptions then begin
      Printf.printf
      "Lcfit: integration did not converge after changing bounds %d times\n"
      max_n_exceptions;
      0.
    end
    else
      let inner_integration dist_bl =
        Integration.value_integrate
          (fun pend_bl ->
            (exp ((ll dist_bl pend_bl) -. base_ll)) *. (prior pend_bl))
          0. upper_limit ~abs_err ~rel_err
      in
      let outer_integration () =
        (/.)
          (Integration.value_integrate
            inner_integration
            0. cut_bl ~abs_err ~rel_err)
          cut_bl
      in
      try
        (if cut_bl =~ 0.
         then inner_integration (cut_bl /. 2.)
         else outer_integration ())
        |> log
        |> (+.) base_ll
      with
        | Gsl_error.Gsl_exn (Gsl_error.ETOL, _) ->
            incr n_exceptions;
            perform (upper_limit /. 2.)
      in perform upper_limit