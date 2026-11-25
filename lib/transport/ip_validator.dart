/// Syntactic validation of manually entered host addresses (Requirement 2.2).
library;

final RegExp _ipv4Pattern = RegExp(
  r'^(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}$',
);

bool isValidIPv4(String input) => _ipv4Pattern.hasMatch(input);

bool isValidIPv6(String input) {
  if (input.isEmpty || !RegExp(r'^[0-9a-fA-F:.]+$').hasMatch(input)) {
    return false;
  }
  final doubleColon = input.indexOf('::');
  if (doubleColon != input.lastIndexOf('::')) return false;
  if (input.contains(':::')) return false;

  var groupsNeeded = 8;
  var text = input;
  // Optional trailing embedded IPv4 occupies two groups.
  final lastColon = text.lastIndexOf(':');
  if (lastColon < 0) return false;
  final tail = text.substring(lastColon + 1);
  if (tail.contains('.')) {
    if (!isValidIPv4(tail)) return false;
    groupsNeeded = 6;
    text = text.substring(0, lastColon + 1);
    // Keep "::" intact if the address ended with it, otherwise drop the colon.
    if (!text.endsWith('::')) text = text.substring(0, text.length - 1);
  }

  bool validGroup(String g) => RegExp(r'^[0-9a-fA-F]{1,4}$').hasMatch(g);

  if (doubleColon >= 0 && input.contains('::')) {
    final parts = text.split('::');
    if (parts.length != 2) return false;
    final head = parts[0].isEmpty ? <String>[] : parts[0].split(':');
    final rest = parts[1].isEmpty ? <String>[] : parts[1].split(':');
    if (![...head, ...rest].every(validGroup)) return false;
    return head.length + rest.length < groupsNeeded;
  }
  final groups = text.split(':');
  return groups.length == groupsNeeded && groups.every(validGroup);
}

/// True when [input] (trimmed) is a syntactically valid IPv4 or IPv6 address.
bool isValidIpAddress(String input) {
  final s = input.trim();
  return isValidIPv4(s) || isValidIPv6(s);
}
