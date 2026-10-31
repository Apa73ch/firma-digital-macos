import Foundation
import CryptoKit
import Security
import libxml2

/// Firma XMLDSig "enveloped" con RSA-SHA256 y C14N inclusivo, igual que el
/// aplicativo de la DGII para Windows (System.Security.Cryptography.Xml.SignedXml).
public enum FirmadorXML {
    static let dsigNS = "http://www.w3.org/2000/09/xmldsig#"
    static let c14nAlg = "http://www.w3.org/TR/2001/REC-xml-c14n-20010315"
    static let rsaSha256 = "http://www.w3.org/2001/04/xmldsig-more#rsa-sha256"
    static let sha256 = "http://www.w3.org/2001/04/xmlenc#sha256"
    static let enveloped = "http://www.w3.org/2000/09/xmldsig#enveloped-signature"

    /// Formato que espera la DGII para FechaHoraFirma.
    public static func fechaHoraFirma(_ fecha: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "dd-MM-yyyy HH:mm:ss"
        return f.string(from: fecha)
    }

    /// Devuelve el XML firmado (UTF-8).
    public static func firmar(_ xml: Data, con cert: Certificado, incluirFechaHoraFirma: Bool, fecha: Date = Date()) throws -> Data {
        let doc = try parse(xml)
        defer { xmlFreeDoc(doc) }
        guard let root = xmlDocGetRootElement(doc) else { throw FirmaError.xmlInvalido("el documento no tiene elemento raíz.") }

        // Si ya venía firmado, se reemplaza la firma anterior.
        for child in hijos(de: root) where esFirma(child) {
            xmlUnlinkNode(child)
            xmlFreeNode(child)
        }

        // FechaHoraFirma solo existe en el esquema del e-CF; en Postulacion,
        // DeclaracionJurada, semilla, etc. la DGII rechaza el XML si aparece.
        let existente = hijos(de: root).first(where: { nombre($0) == "FechaHoraFirma" })
        if incluirFechaHoraFirma && (nombre(root) == "ECF" || existente != nil) {
            let valor = fechaHoraFirma(fecha)
            if let existente {
                conX(valor) { xmlNodeSetContent(existente, $0) }
            } else {
                agregar(root, root.pointee.ns, "FechaHoraFirma", valor)
            }
        }

        // Estructura de la firma (DigestValue y SignatureValue se rellenan después).
        let signature = conX("Signature") { xmlNewDocNode(doc, nil, $0, nil) }!
        let ns = conX(dsigNS) { xmlNewNs(signature, $0, nil) }
        xmlSetNs(signature, ns)
        xmlAddChild(root, signature)

        let signedInfo = agregar(signature, ns, "SignedInfo")
        atributo(agregar(signedInfo, ns, "CanonicalizationMethod"), "Algorithm", c14nAlg)
        atributo(agregar(signedInfo, ns, "SignatureMethod"), "Algorithm", rsaSha256)
        let reference = agregar(signedInfo, ns, "Reference")
        atributo(reference, "URI", "")
        let transforms = agregar(reference, ns, "Transforms")
        atributo(agregar(transforms, ns, "Transform"), "Algorithm", enveloped)
        atributo(agregar(reference, ns, "DigestMethod"), "Algorithm", sha256)
        let digestValue = agregar(reference, ns, "DigestValue")
        let signatureValue = agregar(signature, ns, "SignatureValue")
        let keyInfo = agregar(signature, ns, "KeyInfo")
        let x509Data = agregar(keyInfo, ns, "X509Data")
        agregar(x509Data, ns, "X509Certificate", cert.der.base64EncodedString())

        // Digest del documento sin el nodo Signature (transformación enveloped).
        let docC14N = try canonicalizar(doc, modo: .excluir(signature))
        let digest = Data(SHA256.hash(data: docC14N)).base64EncodedString()
        conX(digest) { xmlNodeSetContent(digestValue, $0) }

        // Firma de SignedInfo canonicalizado.
        let siC14N = try canonicalizar(doc, modo: .soloSubarbol(signedInfo))
        let firma = try cert.firmarRSASHA256(siC14N).base64EncodedString()
        conX(firma) { xmlNodeSetContent(signatureValue, $0) }

        return serializar(doc)
    }

    public struct Verificacion {
        public let valida: Bool
        public let detalle: String
    }

    /// Comprueba digest y firma de un XML firmado (usa el certificado incluido en KeyInfo).
    public static func verificar(_ xml: Data) throws -> Verificacion {
        let doc = try parse(xml)
        defer { xmlFreeDoc(doc) }
        guard let root = xmlDocGetRootElement(doc),
              let signature = hijos(de: root).first(where: esFirma) else {
            return Verificacion(valida: false, detalle: "El XML no contiene firma.")
        }
        guard let signedInfo = buscar(signature, "SignedInfo"),
              let digestNode = buscar(signedInfo, "DigestValue"),
              let sigValueNode = buscar(signature, "SignatureValue"),
              let certNode = buscar(signature, "X509Certificate") else {
            return Verificacion(valida: false, detalle: "La firma está incompleta.")
        }
        let digestEsperado = texto(digestNode)
        let digestReal = Data(SHA256.hash(data: try canonicalizar(doc, modo: .excluir(signature)))).base64EncodedString()
        guard digestEsperado == digestReal else {
            return Verificacion(valida: false, detalle: "El contenido fue modificado después de firmar (DigestValue no coincide).")
        }
        guard let firma = Data(base64Encoded: texto(sigValueNode), options: .ignoreUnknownCharacters),
              let der = Data(base64Encoded: texto(certNode), options: .ignoreUnknownCharacters),
              let cert = SecCertificateCreateWithData(nil, der as CFData),
              let pub = SecCertificateCopyKey(cert) else {
            return Verificacion(valida: false, detalle: "No se pudo leer el certificado o la firma.")
        }
        let siC14N = try canonicalizar(doc, modo: .soloSubarbol(signedInfo))
        let ok = SecKeyVerifySignature(pub, .rsaSignatureMessagePKCS1v15SHA256, siC14N as CFData, firma as CFData, nil)
        let titular = SecCertificateCopySubjectSummary(cert) as String? ?? ""
        return Verificacion(valida: ok, detalle: ok ? "Firma válida (\(titular))." : "SignatureValue no corresponde al certificado.")
    }

    // MARK: - Canonicalización

    enum Modo {
        case excluir(xmlNodePtr)
        case soloSubarbol(xmlNodePtr)
    }

    private final class Contexto {
        let modo: Modo
        init(_ modo: Modo) { self.modo = modo }
    }

    /// C14N 1.0 inclusivo sin comentarios.
    static func canonicalizar(_ doc: xmlDocPtr, modo: Modo) throws -> Data {
        guard let buf = xmlAllocOutputBuffer(nil) else { throw FirmaError.firma("sin memoria") }
        let ctx = Contexto(modo)
        let ptr = Unmanaged.passUnretained(ctx).toOpaque()

        // Un nodo pertenece al subárbol de `t` si es `t` o si su padre está dentro de `t`.
        // Se usa `parent` (siempre un xmlNode real) porque los nodos de namespace son xmlNs.
        let visible: xmlC14NIsVisibleCallback = { userData, node, parent in
            let ctx = Unmanaged<Contexto>.fromOpaque(userData!).takeUnretainedValue()
            func dentro(_ t: xmlNodePtr) -> Bool {
                if node == t { return true }
                var p = parent
                while let cur = p {
                    if cur == t { return true }
                    p = cur.pointee.parent
                }
                return false
            }
            switch ctx.modo {
            case .excluir(let t): return dentro(t) ? 0 : 1
            case .soloSubarbol(let t): return dentro(t) ? 1 : 0
            }
        }

        let r = withExtendedLifetime(ctx) {
            xmlC14NExecute(doc, visible, ptr, Int32(XML_C14N_1_0.rawValue), nil, 0, buf)
        }
        xmlOutputBufferFlush(buf)
        let size = Int(xmlOutputBufferGetSize(buf))
        let data = xmlOutputBufferGetContent(buf).map { Data(bytes: $0, count: size) } ?? Data()
        xmlOutputBufferClose(buf)
        guard r >= 0 else { throw FirmaError.firma("no se pudo canonicalizar el XML.") }
        return data
    }

    // MARK: - Utilidades libxml2

    static func parse(_ xml: Data) throws -> xmlDocPtr {
        let opts = Int32(XML_PARSE_NONET.rawValue)
        let doc = xml.withUnsafeBytes { raw -> xmlDocPtr? in
            guard let base = raw.baseAddress else { return nil }
            return xmlReadMemory(base.assumingMemoryBound(to: CChar.self), Int32(raw.count), nil, nil, opts)
        }
        guard let doc else {
            let msg = xmlGetLastError().map { String(cString: $0.pointee.message).trimmingCharacters(in: .whitespacesAndNewlines) } ?? "no se pudo leer"
            throw FirmaError.xmlInvalido(msg)
        }
        if let root = xmlDocGetRootElement(doc) { quitarEspaciosEnBlanco(root) }
        return doc
    }

    /// Igual que XmlDocument de .NET con PreserveWhitespace = false (lo que usan el
    /// aplicativo de Windows y la DGII al validar): los nodos de texto formados solo
    /// por espacios, tabulaciones o saltos de línea no forman parte del documento,
    /// salvo dentro de xml:space="preserve".
    static func quitarEspaciosEnBlanco(_ node: xmlNodePtr) {
        var c = node.pointee.children
        while let cur = c {
            c = cur.pointee.next
            if cur.pointee.type == XML_TEXT_NODE {
                let t = cur.pointee.content.map { String(cString: $0) } ?? ""
                if t.utf8.allSatisfy({ $0 == 0x20 || $0 == 0x09 || $0 == 0x0A || $0 == 0x0D }),
                   xmlNodeGetSpacePreserve(node) != 1 {
                    xmlUnlinkNode(cur)
                    xmlFreeNode(cur)
                }
            } else if cur.pointee.type == XML_ELEMENT_NODE {
                quitarEspaciosEnBlanco(cur)
            }
        }
    }

    /// Se guarda con sangría, como el aplicativo de Windows. Es seguro porque la
    /// sangría son espacios en blanco que no cuentan para la firma.
    static func serializar(_ doc: xmlDocPtr) -> Data {
        var mem: UnsafeMutablePointer<xmlChar>?
        var size: Int32 = 0
        xmlDocDumpFormatMemoryEnc(doc, &mem, &size, "UTF-8", 1)
        defer { xmlFree(mem) }
        var data = mem.map { Data(bytes: $0, count: Int(size)) } ?? Data()

        // Mismo formato que XmlDocument.Save de .NET: BOM UTF-8, encoding en
        // minúsculas, saltos de línea CRLF y sin salto de línea final.
        // (Un CRLF dentro de un texto se vuelve a leer como LF, así que no altera el contenido.)
        let decl = Data(#"<?xml version="1.0" encoding="UTF-8"?>"#.utf8)
        if data.starts(with: decl) {
            data.replaceSubrange(0..<decl.count, with: Data(#"<?xml version="1.0" encoding="utf-8"?>"#.utf8))
        }
        while data.last == 0x0A { data.removeLast() }
        var crlf = Data(capacity: data.count + data.count / 20)
        for b in data {
            if b == 0x0A { crlf.append(0x0D) }
            crlf.append(b)
        }
        return Data([0xEF, 0xBB, 0xBF]) + crlf
    }

    @discardableResult
    static func conX<R>(_ s: String, _ body: (UnsafePointer<xmlChar>) -> R) -> R {
        s.withCString { $0.withMemoryRebound(to: xmlChar.self, capacity: s.utf8.count + 1, body) }
    }

    @discardableResult
    static func agregar(_ parent: xmlNodePtr, _ ns: xmlNsPtr?, _ name: String, _ content: String? = nil) -> xmlNodePtr {
        conX(name) { n in
            if let content {
                return conX(content) { c in xmlNewTextChild(parent, ns, n, c) }
            }
            return xmlNewChild(parent, ns, n, nil)
        }!
    }

    static func atributo(_ node: xmlNodePtr, _ name: String, _ value: String) {
        conX(name) { n in conX(value) { v in _ = xmlSetProp(node, n, v) } }
    }

    static func hijos(de node: xmlNodePtr) -> [xmlNodePtr] {
        var out: [xmlNodePtr] = []
        var c = node.pointee.children
        while let cur = c {
            if cur.pointee.type == XML_ELEMENT_NODE { out.append(cur) }
            c = cur.pointee.next
        }
        return out
    }

    static func nombre(_ node: xmlNodePtr) -> String {
        node.pointee.name.map { String(cString: $0) } ?? ""
    }

    static func esFirma(_ node: xmlNodePtr) -> Bool {
        guard nombre(node) == "Signature", let ns = node.pointee.ns, let href = ns.pointee.href else { return false }
        return String(cString: href) == dsigNS
    }

    static func buscar(_ node: xmlNodePtr, _ name: String) -> xmlNodePtr? {
        for h in hijos(de: node) {
            if nombre(h) == name { return h }
            if let r = buscar(h, name) { return r }
        }
        return nil
    }

    static func texto(_ node: xmlNodePtr) -> String {
        guard let c = xmlNodeGetContent(node) else { return "" }
        defer { xmlFree(c) }
        return String(cString: c).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
