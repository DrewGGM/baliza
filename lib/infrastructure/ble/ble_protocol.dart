/// Constantes del enlace BLE de Baliza.
abstract final class BleProtocol {
  /// Identificador de fabricante que rotula las tramas Baliza.
  ///
  /// 0xFFFF está reservado por la especificación Bluetooth para **pruebas y
  /// desarrollo**, y es lo correcto mientras el proyecto no tenga un
  /// identificador propio asignado por el Bluetooth SIG. Usar el de otra
  /// empresa sería incorrecto y haría que sus dispositivos interpretaran mal
  /// nuestras tramas.
  ///
  /// Como 0xFFFF lo puede usar cualquiera, la trama no se identifica sólo por
  /// este número: lleva además la firma [signature] y un CRC que descartan
  /// cualquier cosa que no sea una Baliza.
  static const int manufacturerId = 0xFFFF;

  /// UUID de servicio de 16 bits que se anuncia junto a los datos.
  ///
  /// Permite que el escaneo filtre en el sistema operativo y no en Dart, lo
  /// que ahorra batería de forma notable, y es el mecanismo que hace visible
  /// la baliza en iOS cuando la app pasa a segundo plano.
  static const String serviceUuid = '0000B4A1-0000-1000-8000-00805F9B34FB';

  /// Forma corta del mismo servicio.
  static const String serviceUuid16 = 'B4A1';

  /// Firma de dos bytes al inicio de los datos de fabricante: 'BZ'.
  ///
  /// Es el primer filtro y el más barato. Descarta de inmediato el ruido de
  /// otros dispositivos que también usan 0xFFFF.
  static const List<int> signature = <int>[0x42, 0x5A];

  /// Nombre local anunciado. Se mantiene corto porque cada carácter resta
  /// espacio del presupuesto de 31 bytes del anuncio.
  static const String localName = 'BALIZA';

  /// Longitud total de los datos de fabricante: firma + trama.
  static const int manufacturerDataLength = 18;
}
