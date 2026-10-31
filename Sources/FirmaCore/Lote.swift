import Foundation

/// Firma uno o varios archivos XML y los guarda en una carpeta de salida
/// conservando el nombre original (la DGII exige RNCEmisor+eNCF.xml).
public enum Lote {
    public struct Resultado: Identifiable {
        public let id = UUID()
        public let archivo: String
        public let destino: URL?
        public let error: String?
        public var ok: Bool { error == nil }
    }

    public static var carpetaPorDefecto: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Archivo XML Firmado", isDirectory: true)
    }

    /// Expande carpetas a los .xml que contienen (sin recursión).
    public static func archivosXML(en urls: [URL]) -> [URL] {
        var out: [URL] = []
        for url in urls {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                let items = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
                out += items.filter { $0.pathExtension.lowercased() == "xml" }
                    .sorted { $0.lastPathComponent < $1.lastPathComponent }
            } else if url.pathExtension.lowercased() == "xml" {
                out.append(url)
            }
        }
        return out
    }

    public static func firmar(_ archivos: [URL], cert: Certificado, salida: URL, incluirFecha: Bool,
                              progreso: ((Int, Int) -> Void)? = nil) -> [Resultado] {
        var resultados: [Resultado] = []
        do {
            try FileManager.default.createDirectory(at: salida, withIntermediateDirectories: true)
        } catch {
            return archivos.map { Resultado(archivo: $0.lastPathComponent, destino: nil, error: "No se pudo crear la carpeta de salida: \(error.localizedDescription)") }
        }
        for (i, url) in archivos.enumerated() {
            progreso?(i, archivos.count)
            do {
                var destino = salida.appendingPathComponent(url.lastPathComponent)
                // Nunca sobrescribir el original.
                if destino.standardizedFileURL == url.standardizedFileURL {
                    let sub = salida.appendingPathComponent("Firmados", isDirectory: true)
                    try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
                    destino = sub.appendingPathComponent(url.lastPathComponent)
                }
                let xml = try Data(contentsOf: url)
                let firmado = try FirmadorXML.firmar(xml, con: cert, incluirFechaHoraFirma: incluirFecha)
                try firmado.write(to: destino, options: .atomic)
                resultados.append(Resultado(archivo: url.lastPathComponent, destino: destino, error: nil))
            } catch {
                resultados.append(Resultado(archivo: url.lastPathComponent, destino: nil, error: error.localizedDescription))
            }
        }
        progreso?(archivos.count, archivos.count)
        return resultados
    }
}
