# 1. Proyecto y configuración

## 1.1 Crear el proyecto y vincular la facturación

1. En la consola, abre el selector de proyectos y elige **Proyecto nuevo**. Nuestro proyecto es
   `bigdata-g1-ecommerce-1105` (el sufijo `1105` es la fecha en que lo creamos).
2. Vincula una cuenta de facturación (menú **Facturación** → **Vincular una cuenta de facturación**).
3. Agrega como editores a las demás personas del equipo (**IAM y administración** → **IAM** → **Otorgar acceso**,
   rol *Editor*). Más adelante se restringen los permisos con cuentas de servicio (capítulo 3).

Por línea de comandos, el equivalente es:

```bash
gcloud auth login
gcloud projects create bigdata-g1-ecommerce-1105 --name="BigData G1 eCommerce"
gcloud billing projects link bigdata-g1-ecommerce-1105 --billing-account=<ID_DE_FACTURACION>
gcloud config set project bigdata-g1-ecommerce-1105
```

> En nuestro caso la organización de la universidad bloquea la creación de proyectos, así que el proyecto se creó con
> una cuenta personal y se le asignó la facturación institucional. Si el tuyo pertenece a una organización, ese paso
> no hace falta, y además se podrá usar el enmascaramiento dinámico de columnas (capítulo 8).

## 1.2 Clonar el repositorio y preparar la configuración

```bash
git clone https://github.com/RVargasC22/bigdata-g1-ecommerce-gcp.git
cd bigdata-g1-ecommerce-gcp
cp config.env.example config.env
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

`config.env` queda fuera de Git (está en `.gitignore`) porque contiene cuentas personales. Todos los scripts hacen
`source config.env`. Estas son las variables y qué significa cada una:

| Variable | Valor de ejemplo | Para qué sirve |
|---|---|---|
| `PROJECT_ID` | `my-gcp-project` | Proyecto de GCP. |
| `REGION`, `ZONE` | `us-central1`, `us-central1-a` | Dónde corren Dataflow y la VM. |
| `DR_REGION` | `us-east1` | Región alterna para el plan de recuperación. |
| `BQ_LOCATION` | `US` | Ubicación (multirregión) de BigQuery y del bucket. |
| `BUCKET` | `my-gcp-project-raw` | Bucket del data lake. |
| `DATASET`, `DR_DATASET` | `ecommerce`, `ecommerce_dr` | Dataset de trabajo y dataset de snapshots. |
| `TOPIC` | `rees46-events` | Tópico de Pub/Sub. |
| `SUBSCRIPTION`, `SUBSCRIPTION_BEAM` | `rees46-events-dataflow`, `rees46-events-beam` | Una suscripción por consumidor (job de plantilla y job Beam). |
| `VM_NAME` | `ingest-vm` | VM temporal de ingesta. |
| `SA_INGESTA`, `SA_DATAFLOW`, `SA_TRANSFORM` | `sa-…@<proyecto>.iam.gserviceaccount.com` | Una cuenta de servicio por componente. |
| `OWNER_ACCOUNT`, `TEAM_FULL_ACCESS`, `ANALYST_ACCOUNT` | correos | Quién ve todo y quién es el analista restringido (capítulo 8). |
| `BILLING_ACCOUNT`, `BILLING_ADMIN`, `BUDGET_PEN` | ID, correo, monto | Presupuesto con alertas al 50, 90 y 100 %. |
| `ALERT_EMAIL` | correo | A dónde llegan las alertas de Cloud Monitoring. |
| `DF_MAX_WORKERS`, `DF_MACHINE` | `3`, `n1-standard-2` | Tope de tamaño de Dataflow, para limitar el gasto. |
| `MAX_BYTES_BILLED` | `107374182400` | Tope de 100 GB facturados por cada llamada a `bq`. |
| `KAGGLE_REES46`, `KAGGLE_OLIST` | slugs de Kaggle | Datasets que se descargan. |

Reemplaza `my-gcp-project` por tu `PROJECT_ID` en todas las variables que lo contienen.

## 1.3 Habilitar las APIs

`infra/01_setup.sh` y los demás scripts habilitan lo que necesitan; si prefieres hacerlo de una vez:

```bash
gcloud services enable compute.googleapis.com pubsub.googleapis.com dataflow.googleapis.com \
  bigquery.googleapis.com storage.googleapis.com secretmanager.googleapis.com iam.googleapis.com \
  monitoring.googleapis.com dataplex.googleapis.com datalineage.googleapis.com datacatalog.googleapis.com \
  iap.googleapis.com bigquerydatatransfer.googleapis.com
```

## 1.4 Si estás detrás de un firewall que descifra TLS

Nuestra red de oficina inspecciona el tráfico HTTPS con una autoridad certificadora propia y bloquea el puerto 22.
Lo resolvimos así, y solo hace falta si ves errores de certificado:

```bash
gcloud config set core/custom_ca_certs_file /etc/ssl/certs/ca-certificates.crt
export REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt HTTPLIB2_CA_CERTS=$REQUESTS_CA_BUNDLE
# SSH a las VM siempre por IAP, porque el puerto 22 está cortado:
gcloud compute ssh ingest-vm --zone=us-central1-a --tunnel-through-iap
```

## 1.5 Entorno de Python para el pipeline Beam

```bash
uv venv -p 3.12 ~/.venvs/beam312
uv pip install -p ~/.venvs/beam312/bin/python "apache-beam[gcp]==2.66.0"
```

Con esto queda listo lo necesario para los capítulos siguientes.
