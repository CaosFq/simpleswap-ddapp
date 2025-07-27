# 🚀 SimpleSwap dApp

Este repositorio contiene el desarrollo del Front-End y el entorno de testing para el contrato **SimpleSwap**, creado como parte del Trabajo Práctico del Módulo 4. El objetivo principal es proporcionar una interfaz de usuario intuitiva para interactuar con el contrato on-chain, permitiendo el intercambio de tokens y la gestión de liquidez.

---

## 📢 Requisitos 

Este proyecto cumple con los siguientes requerimientos:

1.  **Interacción con el Contrato (Front-End):**
    * Se ha desarrollado un Front-End utilizando **Next.js** y **Scaffold-Eth v2** que permite la conexión de billeteras (ej. MetaMask).
    * La interfaz de usuario habilita las funciones esenciales del contrato `SimpleSwap`:
        * **Intercambio de tokens (swap):** Permite a los usuarios intercambiar `Token A` por `Token B` (y viceversa, si el contrato lo permite bidireccionalmente).
        * **Obtención del precio:** Muestra la estimación de la cantidad de tokens a recibir antes de realizar un swap (usando `getAmountOut`).
    * El front-end está diseñado para ser **responsivo**, adaptándose a diferentes tamaños de pantalla (móvil, tablet, escritorio).

2.  **Entorno de Desarrollo y Testing (Hardhat):**
    * El proyecto está implementado con **Hardhat**, facilitando la compilación, despliegue y testing de los contratos inteligentes.
    * Se han desarrollado tests para el contrato `SimpleSwap`, buscando una **cobertura de código igual o superior al 50%**. Puedes verificar la cobertura ejecutando `npx hardhat coverage`.

3.  **Recomendaciones del Instructor:**
    * Las recomendaciones proporcionadas por el instructor durante la revisión del contrato `SimpleSwap` del Módulo 3 han sido **implementadas y abordadas** en este desarrollo. (Aquí puedes ser más específico si hubo puntos clave que corregiste, ej: "Se mejoró la gestión de errores en la función X" o "Se optimizó el cálculo de la función Y").

4.  **Herramientas Utilizadas:**
    * **Front-End:** Next.js, React, Scaffold-Eth v2, Tailwind CSS, DaisyUI.
    * **Smart Contracts & Desarrollo:** Hardhat, Solidity.
    * **Manejo de estados/conexión:** Wagmi, Viem.

5.  **Almacenamiento y Despliegue:**
    * Los contratos y el código del Front-End están almacenados en este repositorio de GitHub: **[https://github.com/CaosFq/simpleswap-ddapp](https://github.com/CaosFq/simpleswap-ddapp)**
    * El Front-End está desplegado en [**Aquí va el enlace de despliegue**]. (Si aún no lo has desplegado, puedes poner "Pendiente" o "Se desplegará en Vercel/GitHub Pages").

---

## ⚙️ Configuración y Ejecución del Proyecto

Sigue estos pasos para levantar el proyecto en tu entorno local.

### **Requisitos Previos**

Asegúrate de tener instalado:

* Node.js (v18.x o superior recomendado)
* Yarn (o npm)
* Git

### **1. Clonar el Repositorio**

Clona este repositorio desde GitHub:

```bash
git clone [https://github.com/CaosFq/simpleswap-ddapp.git](https://github.com/CaosFq/simpleswap-ddapp.git)
cd simpleswap-ddapp # Navega a la carpeta principal de tu proyecto# Dex-Dapp
# simpleswap-ddapp
