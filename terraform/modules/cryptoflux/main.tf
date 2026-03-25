# ─── Secret ───────────────────────────────────────────────────────────────────

resource "kubernetes_secret" "cryptoflux_secrets" {
  metadata {
    name      = "cryptoflux-secrets"
    namespace = var.namespace
    labels    = { managed-by = "terraform" }
  }

  data = {
    DB_NAME               = var.cf_db_name
    DB_USER               = var.cf_db_user
    DB_PASS               = var.cf_db_pass
    DR_DB_NAME            = var.cf_dr_db_name
    DR_DB_USER            = var.cf_dr_db_user
    DR_DB_PASS            = var.cf_dr_db_pass
    SECRET_KEY            = var.cf_secret_key
    TRADING_DATA_API_KEY  = var.cf_trading_data_api_key
    EXT_API_KEY           = var.cf_ext_api_key
    INTERVAL_SECONDS      = tostring(var.cf_interval_seconds)
    BATCH_SIZE            = tostring(var.cf_batch_size)
    RETENTION_DAYS        = tostring(var.cf_retention_days)
    SYNC_INTERVAL_SECONDS = tostring(var.cf_sync_interval_seconds)
  }
}

# ─── Secret: ext-api-keys (SQLite DB placeholder) ─────────────────
resource "kubernetes_secret" "ext_api_keys" {
  metadata {
    name      = "ext-api-keys"
    namespace = var.namespace
    labels    = { managed-by = "terraform" }
  }

  # Placeholder file - ext-api initializes if empty
  data = {
    "api_keys.db" = "SQLite format 3"
  }
}

# ─── ConfigMaps (PostgreSQL init SQL) ─────────────────────────────────────────
# \c lines removed — initdb scripts run in the context of POSTGRES_DB already.

resource "kubernetes_config_map" "postgres_init_sql" {
  metadata {
    name      = "postgres-init-sql"
    namespace = var.namespace
    labels    = { managed-by = "terraform" }
  }

  data = {
    "init.sql" = <<-EOT
      -- PostgreSQL initialization script for Banking Security Training Application
      -- This script sets up the database with proper permissions and extensions

      -- Create extensions that might be useful
      CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
      CREATE EXTENSION IF NOT EXISTS "pg_stat_statements";

      -- Grant necessary permissions to the user
      GRANT ALL PRIVILEGES ON DATABASE cryptoflux TO cryptouser;
      GRANT ALL ON SCHEMA public TO cryptouser;
      GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO cryptouser;
      GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO cryptouser;

      -- Set default privileges for future objects
      ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO cryptouser;
      ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO cryptouser;

      -- Create a function to display database info
      CREATE OR REPLACE FUNCTION show_db_info()
      RETURNS TABLE(
          property TEXT,
          value TEXT
      ) AS $$
      BEGIN
          RETURN QUERY
          SELECT 'Database Name'::TEXT, current_database()::TEXT
          UNION ALL
          SELECT 'PostgreSQL Version'::TEXT, version()::TEXT
          UNION ALL
          SELECT 'Current User'::TEXT, current_user::TEXT
          UNION ALL
          SELECT 'Connection Info'::TEXT,
                 ('Host: ' || inet_server_addr() || ' Port: ' || inet_server_port())::TEXT
          UNION ALL
          SELECT 'Database Size'::TEXT,
                 pg_size_pretty(pg_database_size(current_database()))::TEXT;
      END;
      $$ LANGUAGE plpgsql;

      -- Display initialization success message
      DO $$
      BEGIN
          RAISE NOTICE 'Cryptoflux Database initialized successfully!';
          RAISE NOTICE 'Database: cryptoflux';
          RAISE NOTICE 'User: cryptouser';
          RAISE NOTICE 'Ready for Flask application connection.';
      END $$;
    EOT
  }
}

resource "kubernetes_config_map" "dr_postgres_init_sql" {
  metadata {
    name      = "dr-postgres-init-sql"
    namespace = var.namespace
    labels    = { managed-by = "terraform" }
  }

  data = {
    "init.sql" = <<-EOT
      -- PostgreSQL initialization script for Banking Security Training Application
      -- This script sets up the database with proper permissions and extensions

      -- Create extensions that might be useful
      CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
      CREATE EXTENSION IF NOT EXISTS "pg_stat_statements";

      -- Grant necessary permissions to the user
      GRANT ALL PRIVILEGES ON DATABASE cryptoflux_dr TO dr_user;
      GRANT ALL ON SCHEMA public TO dr_user;
      GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO dr_user;
      GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO dr_user;

      -- Set default privileges for future objects
      ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO dr_user;
      ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO dr_user;

      -- Create a function to display database info
      CREATE OR REPLACE FUNCTION show_db_info()
      RETURNS TABLE(
          property TEXT,
          value TEXT
      ) AS $$
      BEGIN
          RETURN QUERY
          SELECT 'Database Name'::TEXT, current_database()::TEXT
          UNION ALL
          SELECT 'PostgreSQL Version'::TEXT, version()::TEXT
          UNION ALL
          SELECT 'Current User'::TEXT, current_user::TEXT
          UNION ALL
          SELECT 'Connection Info'::TEXT,
                 ('Host: ' || inet_server_addr() || ' Port: ' || inet_server_port())::TEXT
          UNION ALL
          SELECT 'Database Size'::TEXT,
                 pg_size_pretty(pg_database_size(current_database()))::TEXT;
      END;
      $$ LANGUAGE plpgsql;

      -- Display initialization success message
      DO $$
      BEGIN
          RAISE NOTICE 'Cryptoflux DR Database initialized successfully!';
          RAISE NOTICE 'Database: cryptoflux_dr';
          RAISE NOTICE 'User: dr_user';
          RAISE NOTICE 'Ready for DR sync connection.';
      END $$;
    EOT
  }
}

# ─── PostgreSQL Primary ────────────────────────────────────────────────────────

resource "kubernetes_service" "postgresql_primary" {
  metadata {
    name      = "postgresql-primary"
    namespace = var.namespace
    labels    = { managed-by = "terraform" }
  }

  spec {
    selector   = { app = "postgresql-primary" }
    cluster_ip = "None" # headless — StatefulSet governing service

    port {
      name        = "postgres"
      port        = 5432
      target_port = 5432
    }

    type = "ClusterIP"
  }
}

resource "kubernetes_stateful_set" "postgresql_primary" {
  metadata {
    name      = "postgresql-primary"
    namespace = var.namespace
    labels    = { managed-by = "terraform" }
  }

  spec {
    service_name = kubernetes_service.postgresql_primary.metadata[0].name
    replicas     = 1

    selector {
      match_labels = { app = "postgresql-primary" }
    }

    template {
      metadata {
        labels = { app = "postgresql-primary" }
      }

      spec {
        container {
          name  = "postgres"
          image = "postgres:18-alpine"

          port {
            container_port = 5432
            protocol       = "TCP"
          }

          env {
            name = "POSTGRES_DB"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.cryptoflux_secrets.metadata[0].name
                key  = "DB_NAME"
              }
            }
          }

          env {
            name = "POSTGRES_USER"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.cryptoflux_secrets.metadata[0].name
                key  = "DB_USER"
              }
            }
          }

          env {
            name = "POSTGRES_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.cryptoflux_secrets.metadata[0].name
                key  = "DB_PASS"
              }
            }
          }

          env {
            name  = "POSTGRES_INITDB_ARGS"
            value = "--encoding=UTF-8"
          }

          volume_mount {
            name       = "pgdata"
            mount_path = "/var/lib/postgresql/data"
          }

          volume_mount {
            name       = "init-sql"
            mount_path = "/docker-entrypoint-initdb.d"
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "256Mi"
            }
          }

          liveness_probe {
            exec {
              command = ["sh", "-c", "pg_isready -U $POSTGRES_USER -d $POSTGRES_DB"]
            }
            initial_delay_seconds = 30
            period_seconds        = 10
            failure_threshold     = 3
          }

          readiness_probe {
            exec {
              command = ["sh", "-c", "pg_isready -U $POSTGRES_USER -d $POSTGRES_DB"]
            }
            initial_delay_seconds = 10
            period_seconds        = 10
            failure_threshold     = 3
          }
        }

        volume {
          name = "init-sql"
          config_map {
            name = kubernetes_config_map.postgres_init_sql.metadata[0].name
          }
        }
      }
    }

    volume_claim_template {
      metadata {
        name = "pgdata"
      }
      spec {
        access_modes       = ["ReadWriteOnce"]
        storage_class_name = "hostpath"
        resources {
          requests = {
            storage = "5Gi"
          }
        }
      }
    }
  }
}

# ─── PostgreSQL DR ─────────────────────────────────────────────────────────────

resource "kubernetes_service" "postgresql_dr" {
  metadata {
    name      = "postgresql-dr"
    namespace = var.namespace
    labels    = { managed-by = "terraform" }
  }

  spec {
    selector   = { app = "postgresql-dr" }
    cluster_ip = "None" # headless — StatefulSet governing service

    port {
      name        = "postgres"
      port        = 5432
      target_port = 5432
    }

    type = "ClusterIP"
  }
}

resource "kubernetes_stateful_set" "postgresql_dr" {
  metadata {
    name      = "postgresql-dr"
    namespace = var.namespace
    labels    = { managed-by = "terraform" }
  }

  spec {
    service_name = kubernetes_service.postgresql_dr.metadata[0].name
    replicas     = 1

    selector {
      match_labels = { app = "postgresql-dr" }
    }

    template {
      metadata {
        labels = { app = "postgresql-dr" }
      }

      spec {
        container {
          name  = "postgres"
          image = "postgres:18-alpine"

          port {
            container_port = 5432
            protocol       = "TCP"
          }

          env {
            name = "POSTGRES_DB"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.cryptoflux_secrets.metadata[0].name
                key  = "DR_DB_NAME"
              }
            }
          }

          env {
            name = "POSTGRES_USER"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.cryptoflux_secrets.metadata[0].name
                key  = "DR_DB_USER"
              }
            }
          }

          env {
            name = "POSTGRES_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.cryptoflux_secrets.metadata[0].name
                key  = "DR_DB_PASS"
              }
            }
          }

          env {
            name  = "POSTGRES_INITDB_ARGS"
            value = "--encoding=UTF-8"
          }

          volume_mount {
            name       = "dr-pgdata"
            mount_path = "/var/lib/postgresql/data"
          }

          volume_mount {
            name       = "dr-init-sql"
            mount_path = "/docker-entrypoint-initdb.d"
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "256Mi"
            }
          }

          liveness_probe {
            exec {
              command = ["sh", "-c", "pg_isready -U $POSTGRES_USER -d $POSTGRES_DB"]
            }
            initial_delay_seconds = 30
            period_seconds        = 10
            failure_threshold     = 3
          }

          readiness_probe {
            exec {
              command = ["sh", "-c", "pg_isready -U $POSTGRES_USER -d $POSTGRES_DB"]
            }
            initial_delay_seconds = 10
            period_seconds        = 10
            failure_threshold     = 3
          }
        }

        volume {
          name = "dr-init-sql"
          config_map {
            name = kubernetes_config_map.dr_postgres_init_sql.metadata[0].name
          }
        }
      }
    }

    volume_claim_template {
      metadata {
        name = "dr-pgdata"
      }
      spec {
        access_modes       = ["ReadWriteOnce"]
        storage_class_name = "hostpath"
        resources {
          requests = {
            storage = "5Gi"
          }
        }
      }
    }
  }
}

# ─── ext-api ──────────────────────────────────────────────────────────────────

resource "kubernetes_deployment" "ext_api" {
  metadata {
    name      = "ext-api"
    namespace = var.namespace
    labels    = { app = "ext-api", managed-by = "terraform" }
  }

  spec {
    replicas = 1

    selector {
      match_labels = { app = "ext-api" }
    }

    template {
      metadata {
        labels = { app = "ext-api" }
      }

      spec {
        container {
          name              = "ext-api"
          image             = "cryptoflux-ext-api:latest"
          image_pull_policy = "Never"

          port {
            container_port = 8000
            protocol       = "TCP"
          }

          env {
            name  = "USE_SQLITE"
            value = "True"
          }

          env {
            name  = "API_KEY_DB_PATH"
            value = "/secrets/api_keys.db"
          }

          volume_mount {
            name       = "api-keys"
            mount_path = "/secrets"
            read_only  = true
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "256Mi"
            }
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = 8000
            }
            initial_delay_seconds = 30
            period_seconds        = 15
            failure_threshold     = 3
          }

          readiness_probe {
            http_get {
              path = "/health"
              port = 8000
            }
            initial_delay_seconds = 10
            period_seconds        = 10
            failure_threshold     = 3
          }
        }

        volume {
          name = "api-keys"
          secret {
            secret_name = "ext-api-keys"
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "ext_api" {
  metadata {
    name      = "ext-api"
    namespace = var.namespace
    labels    = { managed-by = "terraform" }
  }

  spec {
    selector = { app = "ext-api" }

    port {
      name        = "http"
      port        = 8000
      target_port = 8000
    }

    type = "ClusterIP"
  }
}

# ─── trading-data ─────────────────────────────────────────────────────────────

resource "kubernetes_deployment" "trading_data" {
  metadata {
    name      = "trading-data"
    namespace = var.namespace
    labels    = { app = "trading-data", managed-by = "terraform" }
  }

  spec {
    replicas = 1

    selector {
      match_labels = { app = "trading-data" }
    }

    template {
      metadata {
        labels = { app = "trading-data" }
      }

      spec {
        # Wait for postgresql-primary to be ready before starting
        init_container {
          name  = "wait-for-postgres"
          image = "postgres:18-alpine"
          command = [
            "sh", "-c",
            "until pg_isready -h postgresql-primary -p 5432; do echo waiting for postgresql-primary; sleep 2; done"
          ]
        }

        container {
          name              = "trading-data"
          image             = "cryptoflux-trading-data:latest"
          image_pull_policy = "Never"

          port {
            container_port = 7100
            protocol       = "TCP"
          }

          # Non-secret connection config
          env {
            name  = "DB_HOST"
            value = "postgresql-primary"
          }

          env {
            name  = "DB_PORT"
            value = "5432"
          }

          # DB_NAME, DB_USER, DB_PASS, TRADING_DATA_API_KEY from secret
          env_from {
            secret_ref {
              name = kubernetes_secret.cryptoflux_secrets.metadata[0].name
            }
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "256Mi"
            }
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = 7100
            }
            initial_delay_seconds = 30
            period_seconds        = 15
            failure_threshold     = 3
          }

          readiness_probe {
            http_get {
              path = "/health"
              port = 7100
            }
            initial_delay_seconds = 10
            period_seconds        = 10
            failure_threshold     = 3
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "trading_data" {
  metadata {
    name      = "trading-data"
    namespace = var.namespace
    labels    = { managed-by = "terraform" }
  }

  spec {
    selector = { app = "trading-data" }

    port {
      name        = "http"
      port        = 7100
      target_port = 7100
    }

    type = "ClusterIP"
  }
}

# ─── trading-ui ───────────────────────────────────────────────────────────────

resource "kubernetes_deployment" "trading_ui" {
  metadata {
    name      = "trading-ui"
    namespace = var.namespace
    labels    = { app = "trading-ui", managed-by = "terraform" }
  }

  spec {
    replicas = 1

    selector {
      match_labels = { app = "trading-ui" }
    }

    template {
      metadata {
        labels = { app = "trading-ui" }
      }

      spec {
        container {
          name              = "trading-ui"
          image             = "cryptoflux-trading-ui:latest"
          image_pull_policy = "Never"

          port {
            container_port = 5000
            protocol       = "TCP"
          }

          env {
            name  = "FLASK_APP"
            value = "app:create_app"
          }

          env {
            name  = "FLASK_DEBUG"
            value = "False"
          }

          env {
            name  = "DB_HOST"
            value = "postgresql-primary"
          }

          env {
            name  = "EXT_API_URL"
            value = "http://ext-api:8000/api/v1/transactions"
          }

          # SECRET_KEY, DB_NAME, DB_USER, DB_PASS, EXT_API_KEY from secret
          env_from {
            secret_ref {
              name = kubernetes_secret.cryptoflux_secrets.metadata[0].name
            }
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "256Mi"
            }
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = 5000
            }
            initial_delay_seconds = 40
            period_seconds        = 15
            failure_threshold     = 3
          }

          readiness_probe {
            http_get {
              path = "/health"
              port = 5000
            }
            initial_delay_seconds = 20
            period_seconds        = 10
            failure_threshold     = 3
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "trading_ui" {
  metadata {
    name      = "trading-ui"
    namespace = var.namespace
    labels    = { managed-by = "terraform" }
  }

  spec {
    selector = { app = "trading-ui" }

    port {
      name        = "http"
      port        = 5000
      target_port = 5000
      node_port   = 30500
    }

    type = "NodePort"
  }
}

# ─── liquidity-calc ───────────────────────────────────────────────────────────

resource "kubernetes_deployment" "liquidity_calc" {
  metadata {
    name      = "liquidity-calc"
    namespace = var.namespace
    labels    = { app = "liquidity-calc", managed-by = "terraform" }
  }

  spec {
    replicas = 1

    selector {
      match_labels = { app = "liquidity-calc" }
    }

    template {
      metadata {
        labels = { app = "liquidity-calc" }
      }

      spec {
        container {
          name              = "liquidity-calc"
          image             = "cryptoflux-liquidity-calc:latest"
          image_pull_policy = "Never"

          port {
            container_port = 8001
            protocol       = "TCP"
          }

          env {
            name  = "TRADING_DATA_URL"
            value = "http://trading-data:7100"
          }

          env {
            name  = "PORT"
            value = "8001"
          }

          env {
            name  = "LIQ_WINDOW_MIN"
            value = "60"
          }

          # Intentionally hardcoded in source — security training scenario
          env {
            name  = "INTERNAL_SERVICE_KEY"
            value = "hardcoded_secret_123"
          }

          env {
            name = "TRADING_DATA_API_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.cryptoflux_secrets.metadata[0].name
                key  = "TRADING_DATA_API_KEY"
              }
            }
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "256Mi"
            }
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = 8001
            }
            initial_delay_seconds = 30
            period_seconds        = 15
            failure_threshold     = 3
          }

          readiness_probe {
            http_get {
              path = "/health"
              port = 8001
            }
            initial_delay_seconds = 10
            period_seconds        = 10
            failure_threshold     = 3
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "liquidity_calc" {
  metadata {
    name      = "liquidity-calc"
    namespace = var.namespace
    labels    = { managed-by = "terraform" }
  }

  spec {
    selector = { app = "liquidity-calc" }

    port {
      name        = "http"
      port        = 8001
      target_port = 8001
    }

    type = "ClusterIP"
  }
}

# ─── data-ingestion (background worker) ───────────────────────────────────────

resource "kubernetes_deployment" "data_ingestion" {
  metadata {
    name      = "data-ingestion"
    namespace = var.namespace
    labels    = { app = "data-ingestion", managed-by = "terraform" }
  }

  spec {
    replicas = 1

    selector {
      match_labels = { app = "data-ingestion" }
    }

    template {
      metadata {
        labels = { app = "data-ingestion" }
      }

      spec {
        container {
          name              = "data-ingestion"
          image             = "cryptoflux-data-ingestion:latest"
          image_pull_policy = "Never"
          command           = ["python", "-u", "worker.py"]

          env {
            name  = "DB_HOST"
            value = "postgresql-primary"
          }

          env {
            name  = "EXT_API_URL"
            value = "http://ext-api:8000/api/v1/transactions"
          }

          # DB_NAME, DB_USER, DB_PASS, EXT_API_KEY,
          # INTERVAL_SECONDS, BATCH_SIZE, RETENTION_DAYS from secret
          env_from {
            secret_ref {
              name = kubernetes_secret.cryptoflux_secrets.metadata[0].name
            }
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "256Mi"
            }
          }
        }
      }
    }
  }
}

# ─── dr-sync (background worker) ──────────────────────────────────────────────

resource "kubernetes_deployment" "dr_sync" {
  metadata {
    name      = "dr-sync"
    namespace = var.namespace
    labels    = { app = "dr-sync", managed-by = "terraform" }
  }

  spec {
    replicas = 1

    selector {
      match_labels = { app = "dr-sync" }
    }

    template {
      metadata {
        labels = { app = "dr-sync" }
      }

      spec {
        container {
          name              = "dr-sync"
          image             = "cryptoflux-dr-sync:latest"
          image_pull_policy = "Never"
          command           = ["python", "-u", "worker.py"]

          # Primary DB — keys renamed from the shared secret
          env {
            name  = "PRIMARY_DB_HOST"
            value = "postgresql-primary"
          }

          env {
            name  = "PRIMARY_DB_PORT"
            value = "5432"
          }

          env {
            name = "PRIMARY_DB_NAME"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.cryptoflux_secrets.metadata[0].name
                key  = "DB_NAME"
              }
            }
          }

          env {
            name = "PRIMARY_DB_USER"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.cryptoflux_secrets.metadata[0].name
                key  = "DB_USER"
              }
            }
          }

          env {
            name = "PRIMARY_DB_PASS"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.cryptoflux_secrets.metadata[0].name
                key  = "DB_PASS"
              }
            }
          }

          # DR DB
          env {
            name  = "DR_DB_HOST"
            value = "postgresql-dr"
          }

          env {
            name  = "DR_DB_PORT"
            value = "5432"
          }

          env {
            name = "DR_DB_NAME"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.cryptoflux_secrets.metadata[0].name
                key  = "DR_DB_NAME"
              }
            }
          }

          env {
            name = "DR_DB_USER"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.cryptoflux_secrets.metadata[0].name
                key  = "DR_DB_USER"
              }
            }
          }

          env {
            name = "DR_DB_PASS"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.cryptoflux_secrets.metadata[0].name
                key  = "DR_DB_PASS"
              }
            }
          }

          env {
            name = "SYNC_INTERVAL_SECONDS"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.cryptoflux_secrets.metadata[0].name
                key  = "SYNC_INTERVAL_SECONDS"
              }
            }
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "256Mi"
            }
          }
        }
      }
    }
  }
}

# ─── attack-console ───────────────────────────────────────────────────────────

resource "kubernetes_deployment" "attack_console" {
  metadata {
    name      = "attack-console"
    namespace = var.namespace
    labels    = { app = "attack-console", managed-by = "terraform" }
  }

  spec {
    replicas = 1

    selector {
      match_labels = { app = "attack-console" }
    }

    template {
      metadata {
        labels = { app = "attack-console" }
      }

      spec {
        container {
          name              = "attack-console"
          image             = "cryptoflux-attack-console:latest"
          image_pull_policy = "Never"

          port {
            container_port = 8090
            protocol       = "TCP"
          }

          env {
            name  = "TRADING_DATA_URL"
            value = "http://trading-data:7100"
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "256Mi"
            }
          }

          liveness_probe {
            http_get {
              path = "/api/health"
              port = 8090
            }
            initial_delay_seconds = 15
            period_seconds        = 15
            failure_threshold     = 3
          }

          readiness_probe {
            http_get {
              path = "/api/health"
              port = 8090
            }
            initial_delay_seconds = 10
            period_seconds        = 10
            failure_threshold     = 3
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "attack_console" {
  metadata {
    name      = "attack-console"
    namespace = var.namespace
    labels    = { managed-by = "terraform" }
  }

  spec {
    selector = { app = "attack-console" }

    port {
      name        = "http"
      port        = 8090
      target_port = 8090
      node_port   = 30600
    }

    type = "NodePort"
  }
}

# ─── Security scan CronJob ────────────────────────────────────────────────────
# Triggers the aiops-brain /security-scan endpoint every 5 minutes.
# Uses Forbid concurrency so a slow scan never overlaps with the next run.

resource "kubernetes_cron_job_v1" "security_scan" {
  metadata {
    name      = "security-scan"
    namespace = var.namespace
    labels    = { managed-by = "terraform" }
  }

  spec {
    schedule                      = "*/5 * * * *"
    concurrency_policy            = "Forbid"
    failed_jobs_history_limit     = 3
    successful_jobs_history_limit = 1

    job_template {
      metadata {
        labels = { managed-by = "terraform" }
      }

      spec {
        template {
          metadata {
            labels = { app = "security-scan" }
          }

          spec {
            restart_policy = "OnFailure"

            container {
              name  = "curl"
              image = "curlimages/curl:8.5.0"
              command = [
                "curl", "-sf", "-X", "POST",
                "http://aiops-brain.aiops.svc.cluster.local:8000/security-scan",
              ]

              resources {
                requests = {
                  cpu    = "10m"
                  memory = "16Mi"
                }
                limits = {
                  cpu    = "50m"
                  memory = "32Mi"
                }
              }
            }
          }
        }
      }
    }
  }
}
