 node-exporter para instalar en cualquier servidor Linux  
 
# MONITOR TARGET : ej AWS

##  Uso:

● copiar docker-compose.node-exporter.yml

  scp docker-compose.node-exporter.yml  ec2-user@IP:/home/ec2-user/

● Levantar contenedor 

  docker compose -f docker-compose.node-exporter.yml up -d

##  Requisitos:

    ●  Docker y Docker Compose instalados

    ●  Puerto 9100 abierto en el firewall/security group

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
