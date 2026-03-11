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

## 1. Opcion A : Copiar a EC2 (TARGET) desde Mi PC (HOST)  

usando  comando `scp`  (OpenSSH secure copy ) copiar el archivo .yaml a instancia EC2 (TARGET) 

Reemplazar valores `IP`  y  `ec2-user` por los que corresponda

```sh
scp docker-compose.node-exporter.yml  ec2-user@IP:/home/ec2-user/
```

## 1 Opcion B : Descargar a EC2 (TARGET) desde GitHub

    usando  comando `curl`  descargatr el archivo .yaml desde GitHub como raw a instancia EC2 (TARGET)
    este comando debe ser corrido desde la instancia EC2 (TARGET)

```sh
curl -O https://raw.githubusercontent.com/ArielLorusso/node-exporter_metrics/refs/heads/main/docker-compose.node-exporter.yml
```

## 2. Levantar _ _ desde EC2 (TARGET)

```sh
docker compose -f docker-compose.node-exporter.yml up -d
```

## 3. Verificar _ _ desde EC2 (TARGET)

```sh
curl http://localhost:9100/metrics | head -3
```
-------------------------------------------------------------------------------------------

# MONITOR HOST  ej : Mi PC

    Una vez corriendo, Prometheus en el servidor central      ( MONITOR HOST  )
    solo necesita agregar al prometheus.yml del HOST :

prometheus.yml:

```yml
   - job_name: 'nombre-del-servidor'
     static_configs:
       - targets: ['IP-DE-MONITOR-TARGET:9100']
         labels:
           host: 'nombre-descriptivo'
```
