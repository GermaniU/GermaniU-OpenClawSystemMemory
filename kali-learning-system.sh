#!/bin/bash
# OpenClaw Learning System - Kali Linux Labs
# Sistema de aprendizaje: Novato -> Experto

KALI_LABS_DIR="/root/workspace/labs"
LEARNING_TRACK_FILE="/root/workspace/.learning-track"
LOG_FILE="/var/log/openclaw-learning.log"

# Niveles: 1-10
get_current_level() {
    if [ -f "$LEARNING_TRACK_FILE" ]; then
        cat "$LEARNING_TRACK_FILE"
    else
        echo "1" > "$LEARNING_TRACK_FILE"
        echo "1"
    fi
}

advance_level() {
    local current=$(get_current_level)
    local next=$((current + 1))
    if [ "$next" -le 10 ]; then
        echo "$next" > "$LEARNING_TRACK_FILE"
        echo "NIVEL $next ALCANZADO!"
    fi
}

log_lesson() {
    echo "[$(date '+%Y-%m-%d %H:%M')] Nivel $1: $2" | tee -a "$LOG_FILE"
}

# Lab A: Memory Forensics (Nivel 1-3)
lab_memory_forensics_novice() {
    log_lesson "1" "Memory Forensics - Conceptos Basicos"
    cat << 'LESSON'

================================================================
LAB A: MEMORY FORENSICS (Novato)
Schedule: Cada 6 horas (con Auto-Sync)
================================================================

CONCEPTOS (Nivel Novato):
-------------------------

1. Que es la memoria forense?
   -> Analisis de RAM para encontrar evidencia
   -> Los datos en RAM desaparecen al apagar

2. Herramientas basicas de Kali:
   * volatility3 - Estandar para analisis de RAM
   * memdump - Extrae la RAM completa
   * strings - Busca texto legible en memoria

3. Paralelo con OpenClaw:
   -> /memory/*.md = RAM del sistema
   -> Qdrant = volatility para busqueda semantica

COMANDOS PRACTICOS:
-------------------

# 1. Ver uso de memoria
htop

# 2. Procesos que consumen memoria
ps aux --sort=-%mem | head -10

# 3. Analizar archivos de memoria
ls -lh /root/workspace/memory/*.md
head -20 /root/workspace/memory/2026-02-24.md

# 4. Ver vectores en Qdrant
curl -s http://localhost:6333/collections/memory_facts | python3 -c "
import sys,json
d=json.load(sys.stdin)
print('Vectores:', d['result']['points_count'])"

DESAFIO PRACTICO:
-----------------
1. Cuantos vectores hay en Qdrant?
2. Cual es el archivo de memoria mas grande?
3. Busca "Claude" en los archivos:
   grep -i "claude" /root/workspace/memory/*.md

================================================================

Próximo: System Hardening (Nivel 2)
LESSON

    echo ""
    echo "PROGRESO: Nivel 1/10 (Novato)"
    echo "Lab: Memory Forensics"
    echo "Herramienta: volatility3 -> memory_search"
}

# Lab B: System Hardening (Nivel 4-7)
lab_system_hardening_intermediate() {
    log_lesson "4" "System Hardening - Seguridad Intermedia"
    cat << 'LESSON'

================================================================
LAB B: SYSTEM HARDENING (Intermedio)
Schedule: Domingos 3:00 AM
================================================================

CONCEPTOS (Nivel Intermedio):
-----------------------------

1. Hardening 101:
   -> Configurar para minima superficie de ataque
   -> Principio de minimo privilegio
   -> Defense in depth

2. Kali para Defensa:
   * lynis - Auditoria de seguridad
   * OpenSCAP - Compliance checking
   * AIDE - Deteccion de intrusos

3. Paralelo con OpenClaw:
   -> Weekly Memory Cleanup = Hardening
   -> Qdrant collections = Servicios a asegurar

LAB PRACTICO:
-------------

Paso 1: Verificar servicios
systemctl list-units --type=service --state=running | grep -E "openclaw|qdrant"

Paso 2: Puertos abiertos
ss -tuln | grep -E "6333|11434|18789"

Paso 3: Hardening de memoria
- Detectar vectores duplicados en Qdrant
- Calcular score de hardening

DESAFIO INTERMEDIO:
-------------------
1. Configura UFW permitir solo:
   - Puerto 22 (SSH)
   - Puerto 18789 (OpenClaw)

2. Script que detecte vectores duplicados en Qdrant

================================================================

Next: Resource Optimization (Nivel 5-7)
LESSON

    echo ""
    echo "PROGRESO: Nivel 4/10 (Intermedio)"
}

# Lab C: Resource Optimization (Nivel 8-10)
lab_resource_optimization_expert() {
    log_lesson "8" "Resource Optimization - Experto"
    cat << 'LESSON'

================================================================
LAB C: RESOURCE OPTIMIZATION (Experto)
Schedule: 1ro de cada mes
================================================================

CONCEPTOS (Nivel Experto):
--------------------------

1. Cost Optimization:
   -> Claude API: $3/MTok input, $15/MTok output
   -> Embedding local: $0 (Ollama llava:7b)
   -> Trade-off: Precision vs Costo

2. Performance Engineering:
   * Profiling: Identificar cuellos de botella
   * Caching: Estrategias LRU/LFU para Qdrant
   * Batch processing: Minimizar llamadas API

3. FinOps para OpenClaw:
   -> Monitorear costo por sesion
   -> Optimizar tamaño de context windows
   -> Seleccionar modelo segun complejidad

LAB AVANZADO - Claude Cost Analyzer:
------------------------------------

# Analisis de costos reales:
Tokens consumidos en memory-auto-sync:
  Backend-coder: 120K tokens
  Devops-infra: ~85K tokens
  QA-tester: ~75K tokens
  Total: ~280K tokens

Costos Claude Sonnet 4.6:
  Input: $3 / 1M tokens
  Costo estimado: $0.84

vs GPT-4 (Input: $30 / 1M tokens):
  Costo: $8.40
  Ahorro: ~90%

DESAFIO EXPERTO:
----------------
Crea un sistema que:
1. Estime costo de cada sesion
2. Sugiera modelo mas economico (Haiku/Sonnet/Opus)
3. Implemente circuit breaker por presupuesto

================================================================

Next: Monitoring & Alerting (Nivel 10)
LESSON

    echo ""
    echo "PROGRESO: Nivel 8/10 (Experto)"
}

# Lab D: Monitoring & Alerting (Nivel 10)
lab_monitoring_master() {
    log_lesson "10" "Monitoring & Alerting - Maestro"
    cat << 'LESSON'

================================================================
LAB D: MONITORING & ALERTING (Maestro)
Schedule: Cada hora
================================================================

CONCEPTOS (Nivel Maestro):
--------------------------

1. Observabilidad Completa:
   -> Metricas: Latencia, throughput
   -> Logs: Estructurados, JSON
   -> Traces: Flujo completo de requests

2. Alerting inteligente:
   * SLOs (Service Level Objectives)
   * SLIs (Service Level Indicators)
   * SLAs (Service Level Agreements)

3. OpenClaw SRE:
   -> Latencia memory_search < 500ms
   -> Disponibilidad Qdrant 99.9%
   -> Zero-downtime deployments

IMPLEMENTACION MAESTRA:
------------------------

# Dashboard de metricas:
curl -s http://localhost:6333/healthz
time curl -s http://localhost:11436/v1/embeddings -d '{"model":"llava:7b","input":"test"}'
curl -s http://localhost:6333/collections/memory_facts | jq '.result.points_count'

PROYECTO FINAL MAESTRO:
-----------------------
Implementa:
1. Prometheus exporter para Qdrant
2. Grafana dashboard para OpenClaw
3. PagerDuty integration
4. Circuit breaker automatico

================================================================

FELICITACIONES - TRACK COMPLETO!
Nivel 10/10 (Maestro)
LESSON

    echo ""
    echo "TRACK COMPLETO! Nivel 10/10 (Maestro)"
}

# Main dispatch
dispatch_lab() {
    local cron_job=$1
    local level=$(get_current_level)
    
    case $cron_job in
        "auto-sync")
            if [ "$level" -le 3 ]; then
                lab_memory_forensics_novice
            fi
            /usr/local/bin/memory-sync 2>/dev/null || echo "Sync manual requerido"
            ;;
        "cleanup")
            if [ "$level" -ge 4 ] && [ "$level" -le 7 ]; then
                lab_system_hardening_intermediate
            fi
            ;;
        "cost-review")
            if [ "$level" -ge 8 ]; then
                lab_resource_optimization_expert
            fi
            ;;
        "health-check")
            if [ "$level" -eq 10 ]; then
                lab_monitoring_master
            fi
            curl -s http://localhost:6333/healthz >/dev/null || echo "ALERT: QDRANT_DOWN"
            ;;
        *)
            echo "Lab desconocido: $cron_job"
            ;;
    esac
}

# Entry point
if [ "$1" == "advance" ]; then
    advance_level
elif [ "$1" == "status" ]; then
    echo "Nivel actual: $(get_current_level)/10"
    echo "Archivo tracking: $LEARNING_TRACK_FILE"
    echo "Log: $LOG_FILE"
else
    dispatch_lab "$1"
fi
