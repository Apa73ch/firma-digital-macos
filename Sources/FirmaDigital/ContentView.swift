import SwiftUI
import AppKit
import UniformTypeIdentifiers
import FirmaCore

@MainActor
final class FirmaModel: ObservableObject {
    @Published var archivos: [URL] = []
    @Published var certificadoURL: URL? {
        didSet { UserDefaults.standard.set(certificadoURL?.path, forKey: "ultimoCertificado") }
    }
    @Published var clave = ""
    @Published var incluirFecha = true
    @Published var salida: URL {
        didSet { UserDefaults.standard.set(salida.path, forKey: "carpetaSalida") }
    }
    @Published var resultados: [Lote.Resultado] = []
    @Published var firmando = false
    @Published var progreso: Double = 0
    @Published var alerta: String?
    @Published var confirmarLimpiar = false
    @Published var arrastrando = false

    init() {
        let d = UserDefaults.standard
        salida = d.string(forKey: "carpetaSalida").map { URL(fileURLWithPath: $0, isDirectory: true) } ?? Lote.carpetaPorDefecto
        if let p = d.string(forKey: "ultimoCertificado"), FileManager.default.fileExists(atPath: p) {
            certificadoURL = URL(fileURLWithPath: p)
        }
    }

    var puedeFirmar: Bool { !archivos.isEmpty && certificadoURL != nil && !clave.isEmpty && !firmando }

    func agregar(_ urls: [URL]) {
        let nuevos = Lote.archivosXML(en: urls).filter { !archivos.contains($0) }
        archivos += nuevos
        if nuevos.isEmpty && !urls.isEmpty { alerta = "No se encontraron archivos .xml." }
    }

    func elegirXML() {
        let panel = NSOpenPanel()
        panel.message = "Seleccione los archivos XML o una carpeta que los contenga."
        panel.allowedContentTypes = [.xml]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        if panel.runModal() == .OK { agregar(panel.urls) }
    }

    func elegirCertificado() {
        let panel = NSOpenPanel()
        panel.message = "Seleccione el certificado digital (.p12 o .pfx)."
        panel.allowedContentTypes = ["p12", "pfx"].compactMap { UTType(filenameExtension: $0) }
        if panel.runModal() == .OK { certificadoURL = panel.url }
    }

    func elegirSalida() {
        let panel = NSOpenPanel()
        panel.message = "Seleccione el directorio para guardar los archivos XML firmados."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url { salida = url }
    }

    func limpiar() {
        archivos = []
        clave = ""
        resultados = []
        progreso = 0
    }

    func firmar() {
        guard let certURL = certificadoURL else { alerta = "Debe seleccionar el certificado para la firma."; return }
        guard clave.count > 3 else { alerta = "La clave no puede estar en blanco y debe ser mayor a 3 caracteres."; return }
        let archivos = archivos, clave = clave, salida = salida, fecha = incluirFecha
        firmando = true
        resultados = []
        progreso = 0

        Task.detached {
            do {
                let cert = try Certificado(url: certURL, clave: clave)
                let res = Lote.firmar(archivos, cert: cert, salida: salida, incluirFecha: fecha) { i, total in
                    Task { @MainActor in self.progreso = Double(i) / Double(max(total, 1)) }
                }
                await MainActor.run {
                    self.resultados = res
                    self.firmando = false
                    let ok = res.filter(\.ok).count
                    if ok == res.count {
                        self.alerta = "Se firmaron \(ok) archivo(s). Los archivos firmados se encuentran en '\(salida.path)'."
                    } else {
                        self.alerta = "Se firmaron \(ok) de \(res.count) archivo(s). Revise los errores en la lista."
                    }
                }
            } catch {
                await MainActor.run {
                    self.firmando = false
                    self.alerta = error.localizedDescription
                }
            }
        }
    }

    func verificar() {
        let panel = NSOpenPanel()
        panel.message = "Seleccione un XML firmado para verificar su firma."
        panel.allowedContentTypes = [.xml]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let v = try FirmadorXML.verificar(Data(contentsOf: url))
            alerta = "\(url.lastPathComponent)\n\n\(v.valida ? "✅" : "❌") \(v.detalle)"
        } catch {
            alerta = error.localizedDescription
        }
    }
}

struct ContentView: View {
    @StateObject private var model = FirmaModel()

    var body: some View {
        VStack(spacing: 0) {
            encabezado
            Form {
                Section("XML a firmar") { seccionXML }
                Section("Certificado digital") {
                    HStack {
                        Image(systemName: "person.text.rectangle")
                            .foregroundStyle(.secondary)
                        Text(model.certificadoURL?.lastPathComponent ?? "Ningún certificado seleccionado")
                            .foregroundStyle(model.certificadoURL == nil ? .secondary : .primary)
                            .lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("Buscar…", action: model.elegirCertificado)
                    }
                    SecureField("Clave privada del certificado", text: $model.clave)
                        .onSubmit { if model.puedeFirmar { model.firmar() } }
                }
                Section("Opciones") {
                    Toggle("Incluir fecha y hora de firma (FechaHoraFirma, solo en e-CF)", isOn: $model.incluirFecha)
                    HStack {
                        Image(systemName: "folder").foregroundStyle(.secondary)
                        Text(model.salida.path)
                            .lineLimit(1).truncationMode(.head)
                            .help(model.salida.path)
                        Spacer()
                        Button("Cambiar…", action: model.elegirSalida)
                    }
                }
                if !model.resultados.isEmpty {
                    Section("Resultado") { listaResultados }
                }
            }
            .formStyle(.grouped)
            pie
        }
        .alert("Notificación", isPresented: Binding(get: { model.alerta != nil }, set: { if !$0 { model.alerta = nil } })) {
            Button("Aceptar", role: .cancel) {}
        } message: {
            Text(model.alerta ?? "")
        }
        .confirmationDialog("¿Está seguro que desea limpiar los campos?", isPresented: $model.confirmarLimpiar) {
            Button("Limpiar", role: .destructive, action: model.limpiar)
        }
    }

    private var encabezado: some View {
        HStack(spacing: 12) {
            Image(systemName: "signature")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.gradient))
            VStack(alignment: .leading, spacing: 2) {
                Text("Aplicativo para firma digital").font(.title3.weight(.semibold))
                Text("Firma de comprobantes fiscales electrónicos (e-CF) para la DGII · XMLDSig RSA-SHA256")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private var seccionXML: some View {
        VStack(spacing: 8) {
            if model.archivos.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "doc.badge.plus").font(.system(size: 26)).foregroundStyle(.secondary)
                    Text("Arrastre aquí archivos XML o una carpeta").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 90)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(model.archivos, id: \.self) { url in
                            HStack {
                                Image(systemName: "doc.text").foregroundStyle(.secondary)
                                Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Button {
                                    model.archivos.removeAll { $0 == url }
                                } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.plain).foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 60, maxHeight: 130)
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(model.arrastrando ? Color.accentColor : Color.secondary.opacity(0.3),
                              style: StrokeStyle(lineWidth: model.arrastrando ? 2 : 1, dash: [5]))
        )
        .onDrop(of: [.fileURL], isTargeted: $model.arrastrando) { providers in
            for p in providers {
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    if let url { Task { @MainActor in model.agregar([url]) } }
                }
            }
            return true
        }
        HStack {
            Text("\(model.archivos.count) archivo(s)").foregroundStyle(.secondary).font(.callout)
            Spacer()
            Button("Agregar XML…", action: model.elegirXML)
        }
    }

    private var listaResultados: some View {
        ForEach(model.resultados) { r in
            HStack {
                Image(systemName: r.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(r.ok ? .green : .orange)
                VStack(alignment: .leading) {
                    Text(r.archivo).lineLimit(1).truncationMode(.middle)
                    if let e = r.error { Text(e).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                if let d = r.destino {
                    Button("Mostrar") { NSWorkspace.shared.activateFileViewerSelecting([d]) }
                        .buttonStyle(.link)
                }
            }
        }
    }

    private var pie: some View {
        HStack {
            Button("Verificar firma…", action: model.verificar)
            Button("Limpiar") { model.confirmarLimpiar = true }
            Spacer()
            if model.firmando {
                ProgressView(value: model.progreso).frame(width: 120)
            }
            Button {
                model.firmar()
            } label: {
                Label("Firmar XML", systemImage: "signature").padding(.horizontal, 8)
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.large)
            .disabled(!model.puedeFirmar)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }
}
