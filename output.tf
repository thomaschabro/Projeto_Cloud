output "link_aplicacao"{
    value = "http://${aws_lb.load_balancer_app.dns_name}/docs"
}