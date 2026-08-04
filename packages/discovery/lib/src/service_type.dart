/// The mDNS/DNS-SD service type the Printer app advertises and the Client
/// app browses for. TLS (`_ipps._tcp`) is out of scope for v1 — see the
/// project README's Non-Goals.
const String ippServiceType = '_ipp._tcp';

/// The resource path this project's Printer app listens on, relative to
/// its `ipp://host:port` root — shared between [PrinterAdvertiser] (which
/// publishes it as the TXT record's `rp` key, per the Bonjour Printing
/// Specification) and [DiscoveredPrinter] (which builds the full printer
/// URI a Client actually connects to).
const String ippResourcePath = 'ipp/print';
