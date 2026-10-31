import Foundation
import FirmaCore

// Uso:
//   firmar-cli firmar <cert.p12> <clave> <salida-dir> [--fecha] <xml|carpeta>...
//   firmar-cli verificar <xml>...
let args = Array(CommandLine.arguments.dropFirst())

func salir(_ msg: String) -> Never {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
    exit(1)
}

guard let cmd = args.first else {
    salir("Uso:\n  firmar-cli firmar <cert.p12> <clave> <salida-dir> [--fecha] <xml|carpeta>...\n  firmar-cli verificar <xml>...")
}

switch cmd {
case "firmar":
    guard args.count >= 5 else { salir("Faltan argumentos.") }
    let cert: Certificado
    do { cert = try Certificado(url: URL(fileURLWithPath: args[1]), clave: args[2]) } catch { salir(error.localizedDescription) }
    let salida = URL(fileURLWithPath: args[3], isDirectory: true)
    var resto = Array(args.dropFirst(4))
    let fecha = resto.contains("--fecha")
    resto.removeAll { $0 == "--fecha" }
    let archivos = Lote.archivosXML(en: resto.map { URL(fileURLWithPath: $0) })
    print("Certificado: \(cert.nombre)")
    var fallos = 0
    for r in Lote.firmar(archivos, cert: cert, salida: salida, incluirFecha: fecha) {
        if r.ok { print("OK    \(r.archivo) -> \(r.destino!.path)") } else { fallos += 1; print("ERROR \(r.archivo): \(r.error!)") }
    }
    exit(fallos == 0 ? 0 : 1)

case "verificar":
    var fallos = 0
    for path in args.dropFirst() {
        do {
            let v = try FirmadorXML.verificar(Data(contentsOf: URL(fileURLWithPath: path)))
            if !v.valida { fallos += 1 }
            print("\(v.valida ? "VÁLIDA  " : "INVÁLIDA") \(path): \(v.detalle)")
        } catch {
            fallos += 1
            print("ERROR    \(path): \(error.localizedDescription)")
        }
    }
    exit(fallos == 0 ? 0 : 1)

default:
    salir("Comando desconocido: \(cmd)")
}
