{ pkgs ? import <nixpkgs> {} }:
pkgs.mkShell {
  buildInputs = with pkgs; [
    kubernetes-helm
    kubectl
    terraform
    terraform-ls
    lastpass-cli
    minikube
  ];
}
