 node-exporter para instalar en cualquier servidor Linux  
 
# MONITOR TARGET : ej AWS

##  Uso:

● copiar docker-compose.node-exporter.yml

```sh
  scp docker-compose.node-exporter.yml  ec2-user@IP:/home/ec2-user/
```
● Levantar contenedor 

```sh
  docker compose -f docker-compose.node-exporter.yml up -d
```

##  Requisitos:

    ●  Docker y Docker Compose instalados
    ●  Puerto 9100 abierto en el firewall/security group



## 1 Opcion A : Descargar a EC2 (TARGET) desde GitHub

```sh
curl -O https://raw.githubusercontent.com/ArielLorusso/node-exporter_metrics/refs/heads/main/requisits.sh
chmod +x requisits.sh && ./requisits.sh
```

    usando  comando `curl`  descargar el script  requisits.sh  como raw
    darle permisos de ejecucion y correrlo :

    1)  Instala Docker
    2)  Inicia  Docker daemon
    3)  Instala Docke  compose
    4)  permite puerto 9100 desde ufw (firewall)
    5)  descarga y corre   docker-compose.node-exporter.yml 
        -> Levanta el container de   node-exporter
    6)  obtiene info de red y metadatos AWS 
    7)  provee instrucciones a ejecutar en el Prometheus y AWS de HOST (pc que mnitorea)

    .yaml desde GitHub como raw a instancia EC2 (TARGET)
    este comando debe ser corrido desde la instancia EC2 (TARGET)



### Opcion B : Hacer todo a mano (se explica pero no recomienda)

## 1. Copiar a EC2 (TARGET) desde Mi PC (HOST)  

usando  comando `scp`  (OpenSSH secure copy ) copiar el archivo .yaml a instancia EC2 (TARGET) 

Reemplazar valores `IP`  y  `ec2-user` por los que corresponda

```sh
scp docker-compose.node-exporter.yml  ec2-user@IP:/home/ec2-user/
```

## 2. Installar Docker _ EC2 (TARGET)


(La opcion A es la correcta para CLI sin interfaz grafica )

### A : setting the apt repository
https://docs.docker.com/engine/install/debian/#install-using-the-repository
```sh
# Add Docker's official GPG key:
sudo apt update
sudo apt install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: $(. /etc/os-release && echo "$VERSION_CODENAME")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF

sudo apt update

sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin


# sudo docker run hello-world
```


### B : Downloading .deb package
https://docs.docker.com/desktop/setup/install/linux/debian/

```sh
wget https://desktop.docker.com/linux/main/amd64/docker-desktop-amd64.deb?utm_source=docker&utm_medium=webreferral&utm_campaign=docs-driven-download-linux-amd64
sudo apt-get update
sudo apt-get install ./docker-desktop-amd64.deb
```

## 3. Levantar _ desde EC2 (TARGET)

```sh
docker compose -f docker-compose.node-exporter.yml up -d
```

## 4. Verificar _ desde EC2 (TARGET)

```sh
curl http://localhost:9100/metrics | head -3
```

## 5 . abrir el puerto 9100

```sh
sudo ufw allow 9100/tcp
```
-------------------------------------------------------------------------------------------

# MONITOR HOST  ej : Mi PC

    con la instance id  averiguamos el security group
    reemplazar <I_ID> con la id de instancia  i-*****************

```sh
aws ec2 describe-instances  \
  --instance-ids <I_ID>  \
  --query 'Reservations[0].Instances[0].SecurityGroups'
```
    con el security group conectamos el puerto 9100 con tcp a la IPv4 de nuestra pc
    reemplazar <SG_ID> con la id de instancia  sg-*****************
    reemplazar <REGION> con la que corresponda

```sh
aws ec2 authorize-security-group-ingress \
  --group-id  <SG_ID> \
  --protocol tcp \
  --port 9100 \
  --region    <REGION> \
  --cidr \$(curl -s -4 ifconfig.me)/32
```
    Una vez corriendo Node-export   en AWS       ( Monitor TARGET  )
    Hay que agregarlo en Prometheus de  Mi PC    ( Monitor HOST   )
    se necesita agregar al prometheus.yml :

prometheus.yml:

```yml
   - job_name: 'nombre-del-servidor'
     static_configs:
       - targets: ['IP-DE-MONITOR-TARGET:9100']
         labels:
           host: 'nombre-descriptivo'
```
--------------------------------------------------------

# DIDACTICO

al final del script  `requisits.sh`  hay comentarios
de limitaciones / herramientas de AWS
de seguridad, configuracione

Este proyecto requiere tener Grafana y Prometeis del lado Host ya resuelto
subire link a compose para visualizar las metricas proximamente.
(basado en Observabilidad-sin-humo pero con Grafana ya configurado )
https://github.com/jgaragorry/Observabilidad-sin-humo-Prometheus-Grafana-Alertmanager-paso-a-paso-Docker-reproducible