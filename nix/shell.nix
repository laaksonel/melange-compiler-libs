{ mkShell, ocamlPackages }:

mkShell {
  buildInputs = (with ocamlPackages; [ ocaml dune findlib menhir menhirLib cppo ocaml-lsp ]);
}
