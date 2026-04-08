output "nginx_ingress_status" {
  description = "Helm release status of the NGINX ingress controller"
  value       = helm_release.nginx_ingress.status
}

output "get_nlb_hostname_command" {
  description = "kubectl command to retrieve the NLB hostname assigned to the ingress controller"
  value       = "kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
}
