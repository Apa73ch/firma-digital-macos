<div align="center">

# ✍️ Firma Digital XML para macOS

**Firma tus XML de Facturación Electrónica (e-CF) de la DGII desde tu Mac.**
Sin máquinas virtuales, sin Windows, sin Parallels.

[![Descargar](https://img.shields.io/github/v/release/Apa73ch/firma-digital-macos?label=Descargar&style=for-the-badge&color=2ea44f)](https://github.com/Apa73ch/firma-digital-macos/releases/latest)
![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black?style=for-the-badge&logo=apple)
![Apple Silicon + Intel](https://img.shields.io/badge/Apple%20Silicon%20%2B%20Intel-universal-blue?style=for-the-badge)
![Licencia MIT](https://img.shields.io/badge/licencia-MIT-lightgrey?style=for-the-badge)

🇩🇴 Hecho para contribuyentes, contadores y desarrolladores que trabajan con **e-CF en República Dominicana**.

</div>

---

## 💡 ¿Qué es?

Una app nativa de macOS **inspirada en el "Aplicativo para firma digital" que la DGII publica para Windows**.
Hace lo mismo y con la misma firma: escoges los XML, tu certificado digital (`.p12` / `.pfx`), pones la clave
y listo. Los archivos firmados quedan listos para subirlos al portal de la DGII o enviarlos a sus servicios.

> ⚠️ Proyecto independiente y de código abierto. **No es un producto oficial de la DGII** ni está afiliado a ella.

## 📄 ¿Qué puedo firmar?

Cualquier XML del proceso de facturación electrónica que pida la DGII:

| Documento | Uso |
|---|---|
| **Postulación** (`Postulacion`) | Paso 1 de la certificación como emisor electrónico / proveedor de software |
| **Declaración Jurada** (`DeclaracionJurada`) | Aceptación de las condiciones de uso de e-CF |
| **Semilla** (`SemillaModel`) | Autenticación contra los servicios web de la DGII para obtener el token |
| **e-CF** (`ECF`) | Comprobantes 31, 32, 33, 34, 41, 43, 44, 45, 46, 47 |
| **RFCE, ACECF, ARECF, ANECF** | Resumen de factura de consumo, aprobación comercial, acuse de recibo, anulaciones |

## ✨ Características

- 🖱️ **Arrastra y suelta** varios XML o una carpeta entera y fírmalos todos de una vez
- 🔐 Certificados **`.p12` / `.pfx`** (Viafirma, Avansi, Cámara de Comercio y demás certificadoras autorizadas por INDOTEL)
- 🕒 Agrega **`FechaHoraFirma`** automáticamente en los e-CF (y solo en los e-CF, donde el esquema lo permite)
- ✅ **Verificador de firmas** integrado para comprobar cualquier XML firmado
- 📁 Conserva el nombre original del archivo (`RNCEmisor + eNCF.xml`) y **nunca sobrescribe tu XML original**
- 🧠 El certificado se lee **solo en memoria**: no se instala en el llavero y la clave no se guarda
- 💻 Incluye **`firmar-cli`**, una herramienta de terminal para automatizar la firma desde scripts o tu sistema

## 🚀 Instalación (sin compilar nada)

1. Descarga **`FirmaDigital-macOS.zip`** desde la [última versión](https://github.com/Apa73ch/firma-digital-macos/releases/latest).
2. Descomprime y arrastra **Firma Digital.app** a tu carpeta **Aplicaciones**.
3. Como la app no está firmada con una cuenta de desarrollador de Apple, la primera vez macOS la bloquea.
   Abre la **Terminal** y ejecuta:

   ```bash
   xattr -dr com.apple.quarantine "/Applications/Firma Digital.app"
   ```

   Después ábrela normalmente. (Otra opción: *Ajustes del Sistema → Privacidad y seguridad → Abrir de todos modos*.)

## 🧾 Cómo se usa

1. **XML a firmar**: arrastra los archivos o una carpeta, o pulsa *Agregar XML…*
2. **Certificado digital**: selecciona tu `.p12` o `.pfx`
3. **Clave privada del certificado**: escribe la contraseña
4. Pulsa **Firmar XML** ✍️

Los archivos firmados se guardan en `~/Documents/Archivo XML Firmado` (lo puedes cambiar).

## ⌨️ Línea de comandos

El zip también trae `firmar-cli`:

```bash
# Firmar archivos o carpetas completas (--fecha agrega FechaHoraFirma en los e-CF)
./firmar-cli firmar certificado.p12 "MI_CLAVE" ./firmados --fecha factura.xml ./carpeta-con-xml

# Verificar la firma de uno o varios XML
./firmar-cli verificar ./firmados/*.xml
```

## 🔬 Detalles técnicos

La firma es la misma que genera el aplicativo de la DGII para Windows (.NET `SignedXml`) y la que la DGII valida:

- **XMLDSig enveloped**: `Reference URI=""` y `Signature` al final del elemento raíz
- **Canonicalización** C14N 1.0 inclusiva, sin comentarios (`http://www.w3.org/TR/2001/REC-xml-c14n-20010315`)
- **RSA-SHA256** (`xmldsig-more#rsa-sha256`) y digest **SHA-256** (`xmlenc#sha256`)
- **`KeyInfo/X509Data/X509Certificate`** con el certificado del firmante
- Los espacios y saltos de línea entre etiquetas **no cuentan** para la firma (como .NET con `PreserveWhitespace = false`)
- `FechaHoraFirma` con el formato `dd-MM-yyyy HH:mm:ss`
- El archivo se guarda igual que en Windows: UTF-8 con BOM, sangría y saltos de línea CRLF

Está hecha en **Swift + SwiftUI**, con `libxml2` para la canonicalización y `Security.framework` para el certificado.
No usa dependencias externas.

## 🛠️ Compilar desde el código fuente

Solo necesitas las Command Line Tools de Xcode (`xcode-select --install`):

```bash
git clone https://github.com/Apa73ch/firma-digital-macos.git
cd firma-digital-macos
./build-app.sh
```

Esto genera `dist/Firma Digital.app` (universal, Apple Silicon + Intel) y `dist/firmar-cli`.

## 🤝 Contribuir

¿Encontraste un XML que la DGII rechaza o quieres agregar algo? Abre un *issue* o un *pull request*. Todo aporte es bienvenido.

## 📜 Licencia

[MIT](LICENSE). Úsala, modifícala y compártela libremente.

---

<sub>Palabras clave: facturación electrónica República Dominicana, e-CF, DGII, firma digital XML, firmar XML Mac, aplicativo firma digital DGII macOS, certificado digital p12, XMLDSig, semilla DGII, postulación emisor electrónico.</sub>
