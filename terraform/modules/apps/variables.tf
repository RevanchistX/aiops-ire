variable "namespace" {
  description = "Kubernetes namespace to deploy flask-app into"
  type        = string
}

variable "replicas" {
  description = "Number of flask-app pod replicas"
  type        = number
  default     = 2
}

variable "image" {
  description = "Container image for the flask-app (must be pre-loaded into k3s via build-and-load.sh)"
  type        = string
  default     = "flask-app:latest"
}
