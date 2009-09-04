(* pplacer v0.2. Copyright (C) 2009  Frederick A Matsen.
 * This file is part of pplacer. pplacer is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version. pplacer is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details. You should have received a copy of the GNU General Public License along with pplacer. If not, see <http://www.gnu.org/licenses/>.
 *)

open MapsSets

(* *** translating protein sequences *** *)

let nucStrMap = 
  StringMapFuns.of_pairlist ["A",0; "C",1; "G",2; "T",3;]

  (*
Adenine 	   A 	                A
Cytosine     	   C 	                C
Guanine            G 	                G
Thymine 	   T 	                T
Purine 	           G or A 	        R
Pyrimidine 	   T or C 	        Y
Amino 	           A or C               M
Keto 	           G or T 	        K
Strong (3H bonds)  G or C 	        S
Weak (2H bonds)    A or T 	        W
Not G 	           A or C or T 	        H
Not A 	           G or T or C 	        B
Not T 	           G or C or A 	        V
Not C 	           G or A or T 	        D
Any 	           G or C or T or A 	N
   *)

let nucLikeMap = 
  CharMapFuns.of_pairlist (
    List.map (fun (c, v) -> (c, Gsl_vector.of_array v)) (
(*            A   C   G   T  *)
      ['A', [|1.; 0.; 0.; 0.|];
       'C', [|0.; 1.; 0.; 0.|];
       'G', [|0.; 0.; 1.; 0.|];
       'T', [|0.; 0.; 0.; 1.|];
       'R', [|1.; 0.; 1.; 0.|];   (*  G or A 	         *)
       'Y', [|0.; 1.; 0.; 1.|];   (*  T or C 	         *)
       'M', [|1.; 1.; 0.; 0.|];   (*  A or C           *)
       'K', [|0.; 0.; 1.; 1.|];   (*  G or T 	         *)
       'S', [|0.; 1.; 1.; 0.|];   (*  G or C 	         *)
       'W', [|1.; 0.; 0.; 1.|];   (*  A or T 	         *)
       'H', [|1.; 1.; 0.; 1.|];   (*  A or C or T 	 *)
       'B', [|0.; 1.; 1.; 1.|];   (*  G or T or C 	 *)
       'V', [|1.; 1.; 1.; 0.|];   (*  G or C or A 	 *)
       'D', [|1.; 0.; 1.; 1.|];   (*  G or A or T 	 *)
       'N', [|1.; 1.; 1.; 1.|];   (*  G or C or T or A *)
       '-', [|1.; 1.; 1.; 1.|];  
       '?', [|1.; 1.; 1.; 1.|];
       'X', [|1.; 1.; 1.; 1.|];]))

let freqRex = Str.regexp "[ \t]*- f(\\([ACGT]\\))= \\([0-9\\.e]+\\)" 
and transRex = Str.regexp "[ \t]*\\([ACGT]\\) <-> \\([ACGT]\\)[ \t]* \\([0-9\\.e]+\\)" 

let likeArrOfNuc nuc = 
  try
    CharMap.find nuc nucLikeMap 
  with
    | Not_found -> 
        invalid_arg (Printf.sprintf "%c not a known nucleotide!" nuc)


(* *** MODELS *** *)

let parseLine line = 
  Array.of_list (List.map float_of_string (Str.split (Str.regexp "\\s+") line))

(* parse a GTR nucleotide model in phyml stat format *)
let parseNucModel stringList = 
  let b = Array.make_matrix 4 4 None
  and d = Array.make 4 None in
  for i=0 to 3 do b.(i).(i) <- Some 0. done;
  List.iter (
    fun line ->
      if Str.string_match freqRex line 0 then ( 
        let nucStr = Str.matched_group 1 line
        and floatStr = Str.matched_group 2 line
        in
        try
          d.(StringMap.find nucStr nucStrMap) <- Some (float_of_string floatStr)
        with 
        | Not_found -> failwith("parseNucModel: base "^nucStr^" not known!")
        | Failure _ -> failwith("parseNucModel: is "^floatStr^" a float?")
        )
      else if Str.string_match transRex line 0 then (
        let fromNuc = Str.matched_group 1 line
        and toNuc = Str.matched_group 2 line
        and floatStr = Str.matched_group 3 line
        in
        try
          b.(StringMap.find fromNuc nucStrMap).(StringMap.find toNuc nucStrMap) 
          <- Some (float_of_string floatStr);
          b.(StringMap.find toNuc nucStrMap).(StringMap.find fromNuc nucStrMap) 
          <- Some (float_of_string floatStr);
        with 
        | Not_found -> failwith("parseNucModel: base "^fromNuc^" or "^toNuc^" not known!")
        | Failure _ -> failwith("parseNucModel: is "^floatStr^" a float?")
        )
  ) stringList;
  let getSome = function 
    | Some x -> x 
    | None -> failwith "parseNucModel: some left undefined!" 
  in
  (Fam_gsl_matvec.matMapFromAAR getSome b, 
   Fam_gsl_matvec.vecMapFromArray getSome d)

    (*

to test, just paste this into the toplevel:

#use "nucModels.ml";;     
#cd "/home/matsen/pplacer/ocaml/compareNucLikes";;
let fragLL = nucLLOfPhymlFile "frag.place.phy_phyml_stats.txt";;
let frag = Alignment.readAlign "frag.place.phy";;
let fragAL = AlignmentLike.ofUnnamedNucAlignment (Alignment.forgetNames frag);;
let (treeNames, untransTree) = Liketree.ofNewickFile "frag.place.phy_phyml_tree.txt";;
let alignNames = Array.map fst frag;; 
let translatedTree = LiketreeFuns.translateTaxonNumbers (PplacerFuns.makeTranslationArr treeNames alignNames) untransTree;;
let ll = fragLL translatedTree fragAL;;

phyml's Log-likelihood: 			-2618.26415

     *)

    (*

to test, just paste this into the toplevel:

#use "nucModels.ml";;     
#cd "/home/matsen/pplacer/ocaml/hiv07env";;
let fragLL = nucLLOfPhymlFile "hiv07env.stats";;
let frag = Alignment.readAlign "frag.phy";;
let fragAL = AlignmentLike.ofUnnamedNucAlignment (Alignment.forgetNames frag);;
let (treeNames, untransTree) = Liketree.ofNewickFile "frag.place.phy_phyml_tree.txt";;
let alignNames = Array.map fst frag;; 
let translatedTree = LiketreeFuns.translateTaxonNumbers (PplacerFuns.makeTranslationArr treeNames alignNames) untransTree;;
let ll = fragLL translatedTree fragAL;;

phyml's Log-likelihood: 			-2618.26415

     *)

(*
     
. Nucleotides frequencies:


let test = 
[
". Nucleotides frequencies:";
"";
"  - f(A)= 0.25229";
"  - f(C)= 0.21152";
"  - f(G)= 0.30687";
"  - f(T)= 0.22932";
"";
". GTR relative rate parameters : ";
"";
"  A <-> C    0.65466";
"  A <-> G    2.77648";
"  A <-> T    1.40191";
"  C <-> G    0.91195";
"  C <-> T    8.01328";
"  G <-> T    1.00000";
]

let (testB, testD) = parseNucModel test
let testDiagd = Diagd.normalizedOfExchangeableMat testB testD
let testLL = nucLLOfStringList test




. Instantaneous rate matrix : 

  [A---------C---------G---------T------]
  -0.77243   0.08153   0.50163   0.18927  
   0.09724  -1.34388   0.16476   1.08188  
   0.41242   0.11357  -0.66100   0.13501  
   0.20824   0.99792   0.18067  -1.38683  


my IRM
- : Mat.ArrArr(Number.R).mat =
[|[|-0.772429232472147564; 0.0815266052601899271; 0.501627223316949311;
    0.189275403895007882|];
  [|0.0972406734166666176; -1.34389600857833225; 0.164762197568105201;
    1.08189313759356076|];
  [|0.412407638969704449; 0.113567634599685913; -0.660987794983038723;
    0.135012521413648445|];
  [|0.208234308602265633; 0.997915735495333855; 0.180670209515987723;
    -1.38682025361358741|]|]

     *)
