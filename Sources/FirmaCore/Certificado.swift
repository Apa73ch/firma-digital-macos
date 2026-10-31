import Foundation
import Security

public enum FirmaError: LocalizedError {
    case certificadoNoExiste
    case claveIncorrecta
    case certificadoInvalido(String)
    case xmlInvalido(String)
    case firma(String)

    public var errorDescription: String? {
        switch self {
        case .certificadoNoExiste: return "El certificado para firma no existe."
        case .claveIncorrecta: return "La clave privada del certificado es incorrecta."
        case .certificadoInvalido(let m): return "Certificado inválido: \(m)"
        case .xmlInvalido(let m): return "XML inválido: \(m)"
        case .firma(let m): return "Error al firmar: \(m)"
        }
    }
}

/// Certificado digital cargado desde un archivo .p12 / .pfx.
public final class Certificado {
    public let privateKey: SecKey
    public let certificate: SecCertificate

    public init(url: URL, clave: String) throws {
        guard let data = try? Data(contentsOf: url) else { throw FirmaError.certificadoNoExiste }

        var options: [String: Any] = [kSecImportExportPassphrase as String: clave]
        if #available(macOS 15.0, *) {
            // Evita que el certificado se instale en el llavero del usuario.
            options[kSecImportToMemoryOnly as String] = true
        }

        var items: CFArray?
        let status = SecPKCS12Import(data as CFData, options as CFDictionary, &items)
        switch status {
        case errSecSuccess: break
        case errSecAuthFailed, errSecPkcs12VerifyFailure: throw FirmaError.claveIncorrecta
        default:
            let msg = SecCopyErrorMessageString(status, nil) as String? ?? "código \(status)"
            throw FirmaError.certificadoInvalido(msg)
        }

        guard let list = items as? [[String: Any]],
              let first = list.first,
              let identityRef = first[kSecImportItemIdentity as String] else {
            throw FirmaError.certificadoInvalido("el archivo no contiene una identidad (certificado + clave privada).")
        }
        let identity = identityRef as! SecIdentity

        var key: SecKey?
        var cert: SecCertificate?
        guard SecIdentityCopyPrivateKey(identity, &key) == errSecSuccess, let key,
              SecIdentityCopyCertificate(identity, &cert) == errSecSuccess, let cert else {
            throw FirmaError.certificadoInvalido("no se pudo leer la clave privada.")
        }
        guard SecKeyIsAlgorithmSupported(key, .sign, .rsaSignatureMessagePKCS1v15SHA256) else {
            throw FirmaError.certificadoInvalido("la clave no es RSA o no permite firmar con SHA-256.")
        }
        privateKey = key
        certificate = cert
    }

    public var nombre: String {
        SecCertificateCopySubjectSummary(certificate) as String? ?? "(sin nombre)"
    }

    public var der: Data { SecCertificateCopyData(certificate) as Data }

    /// Fecha de vencimiento, si se puede leer.
    public var venceEl: Date? {
        guard let values = SecCertificateCopyValues(certificate, [kSecOIDX509V1ValidityNotAfter] as CFArray, nil) as? [String: Any],
              let entry = values[kSecOIDX509V1ValidityNotAfter as String] as? [String: Any],
              let n = entry[kSecPropertyKeyValue as String] as? NSNumber else { return nil }
        return Date(timeIntervalSinceReferenceDate: n.doubleValue)
    }

    func firmarRSASHA256(_ data: Data) throws -> Data {
        var error: Unmanaged<CFError>?
        guard let sig = SecKeyCreateSignature(privateKey, .rsaSignatureMessagePKCS1v15SHA256, data as CFData, &error) else {
            throw FirmaError.firma(error?.takeRetainedValue().localizedDescription ?? "fallo desconocido")
        }
        return sig as Data
    }
}
