open OUnit

let suite = [
  "edge_labels" >::: Test_edge_labels.suite;
  "matrix" >::: Test_matrix.suite;
  "diagd" >::: Test_diagd.suite;
]
