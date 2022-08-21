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
  shellHooks = ''
    export KUBE_CONFIG_PATH=$HOME/.kube/config
    [[ -f .env ]] && source .env
  '';
}
