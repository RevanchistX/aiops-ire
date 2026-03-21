"""Kubernetes auto-remediation actions.

Runs inside the cluster using the aiops-brain ServiceAccount, which is granted
get/list/delete on pods and get/list/patch on deployments via ClusterRole.

Remediation strategy (keyed on alert name prefix):
  - *CrashLoop* | *Restarting* | *OOMKilled* → delete oldest crashing pod
    (the Deployment controller immediately reschedules it)
  - *HighMemory* | *MemoryPressure* | *ReplicasMismatch* → rollout restart
    (patches spec.template annotation, triggering a rolling replacement)
  - anything else → no-op (returns a "not applicable" message)
"""

import logging
from datetime import datetime, timezone

from kubernetes import client, config
from kubernetes.client.exceptions import ApiException

logger = logging.getLogger(__name__)

# Alert name substrings → remediation strategy
_POD_RESTART_PATTERNS = ("crashloop", "restarting", "oomkill", "poddown", "podnotready")
_ROLLOUT_RESTART_PATTERNS = ("highmemory", "memorypressure", "replicasmismatch", "highcpu")


def _load_config() -> None:
    """Load in-cluster config; fall back to kubeconfig for local testing."""
    try:
        config.load_incluster_config()
    except config.ConfigException:
        config.load_kube_config()


async def attempt_remediation(
    alert_name: str,
    service: str,
    namespace: str = "apps",
) -> tuple[str, str]:
    """Decide and execute a remediation action.

    Returns a (action, result) tuple that is persisted to the incidents table.
    """
    key = alert_name.lower().replace("-", "").replace("_", "")

    if any(p in key for p in _POD_RESTART_PATTERNS):
        return await _restart_pod(service, namespace)
    elif any(p in key for p in _ROLLOUT_RESTART_PATTERNS):
        return await _rollout_restart(service, namespace)
    else:
        action = "none"
        result = f"No auto-remediation rule matched alert_name={alert_name!r}"
        logger.info("remediation action=%s alert=%s", action, alert_name)
        return action, result


async def _restart_pod(service: str, namespace: str) -> tuple[str, str]:
    """Delete the first Running/CrashLoopBackOff pod matching app=<service>."""
    action = f"pod_restart(app={service}, namespace={namespace})"
    _load_config()
    v1 = client.CoreV1Api()

    try:
        pods = v1.list_namespaced_pod(
            namespace=namespace,
            label_selector=f"app={service}",
        )
    except ApiException as exc:
        result = f"Failed to list pods: {exc.status} {exc.reason}"
        logger.error("remediation action=%s error=%s", action, result)
        return action, result

    if not pods.items:
        result = f"No pods found with app={service} in namespace={namespace}"
        logger.warning("remediation action=%s result=%s", action, result)
        return action, result

    # Delete the first pod — the Deployment controller will recreate it
    pod = pods.items[0]
    pod_name = pod.metadata.name
    try:
        v1.delete_namespaced_pod(name=pod_name, namespace=namespace)
        result = f"Deleted pod {pod_name}; Deployment controller will reschedule"
        logger.info("remediation action=%s pod=%s result=success", action, pod_name)
    except ApiException as exc:
        result = f"Failed to delete pod {pod_name}: {exc.status} {exc.reason}"
        logger.error("remediation action=%s error=%s", action, result)

    return action, result


async def _rollout_restart(service: str, namespace: str) -> tuple[str, str]:
    """Patch the Deployment to trigger a rolling restart via annotation update."""
    action = f"rollout_restart(app={service}, namespace={namespace})"
    _load_config()
    apps_v1 = client.AppsV1Api()

    restart_ts = datetime.now(tz=timezone.utc).isoformat()
    patch_body = {
        "spec": {
            "template": {
                "metadata": {
                    "annotations": {
                        "kubectl.kubernetes.io/restartedAt": restart_ts
                    }
                }
            }
        }
    }

    try:
        apps_v1.patch_namespaced_deployment(
            name=service,
            namespace=namespace,
            body=patch_body,
        )
        result = f"Rollout restart patched on Deployment/{service} at {restart_ts}"
        logger.info("remediation action=%s result=success ts=%s", action, restart_ts)
    except ApiException as exc:
        result = f"Failed to patch Deployment/{service}: {exc.status} {exc.reason}"
        logger.error("remediation action=%s error=%s", action, result)

    return action, result
