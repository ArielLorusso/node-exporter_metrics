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

    usando  comando `curl`  descargatr el archivo .yaml desde GitHub como raw a instancia EC2 (TARGET)
    este comando debe ser corrido desde la instancia EC2 (TARGET)

```sh
curl -O https://raw.githubusercontent.com/ArielLorusso/node-exporter_metrics/refs/heads/main/docker-compose.node-exporter.yml
curl -O https://raw.githubusercontent.com/ArielLorusso/node-exporter_metrics/refs/heads/main/requisits.sh
```

### 1. Opcion B : Copiar a EC2 (TARGET) desde Mi PC (HOST)  

usando  comando `scp`  (OpenSSH secure copy ) copiar el archivo .yaml a instancia EC2 (TARGET) 

Reemplazar valores `IP`  y  `ec2-user` por los que corresponda

```sh
scp docker-compose.node-exporter.yml  ec2-user@IP:/home/ec2-user/
```

## 2. reauisitos _ desde EC2 (TARGET)

correr `requisits.sh ` con permiso de ejecucion

```sh
chmod +x requisits.sh && ./requisits.sh
```
    1) Revisa version de Sistema Operativo
    2) Revisa instala Docker y compose
    3) Corre :  docker compose -f docker-compose.node-exporter.yml up -d
    4) Revisa puertos e IP publica
    5) Imprime instrucciones para AWS_CLI

Con el requisits.sh ejecutado podriamos seguir desde las indicaciones provistas

En caso de que por algun motivo no funcione se avlaran los pasos a seguir igualmente

## 3. Levantar _ desde EC2 (TARGET)

```sh
docker compose -f docker-compose.node-exporter.yml up -d
```

## 4. Verificar _ desde EC2 (TARGET)

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
