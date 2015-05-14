// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library package_config.packagemap;

class Packages {
  static const int _EQUALS = 0x3d;
  static const int _CR = 0x0d;
  static const int _NL = 0x0a;
  static const int _NUMBER_SIGN = 0x23;

  final Map<String, Uri> packageMapping;

  Packages(this.packageMapping);

  /// Resolves a URI to a non-package URI.
  ///
  /// If [uri] is a `package:` URI, the location is resolved wrt. the
  /// [packageMapping].
  /// Otherwise the original URI is returned.
  Uri resolve(Uri uri) {
    if (uri.scheme.toLowerCase() != "package") {
      return uri;
    }
    if (uri.hasAuthority) {
      throw new ArgumentError.value(uri, "uri", "Must not have authority");
    }
    if (uri.path.startsWith("/")) {
      throw new ArgumentError.value(
          uri, "uri", "Path must not start with '/'.");
    }
    // Normalizes the path by removing '.' and '..' segments.
    uri = _normalizePath(uri);
    String path = uri.path;
    var slashIndex = path.indexOf('/');
    String packageName;
    String rest;
    if (slashIndex < 0) {
      packageName = path;
      rest = "";
    } else {
      packageName = path.substring(0, slashIndex);
      rest = path.substring(slashIndex + 1);
    }
    Uri packageLocation = packageMapping[packageName];
    if (packageLocation == null) {
      throw new ArgumentError.value(
          uri, "uri", "Unknown package name: $packageName");
    }
    return packageLocation.resolveUri(new Uri(path: rest));
  }

  /// A stand in for uri.normalizePath(), coming in 1.11
  static Uri _normalizePath(Uri existingUri) =>
      new Uri().resolveUri(existingUri);

  /// Parses a `packages.cfg` file into a `Packages` object.
  ///
  /// The [baseLocation] is used as a base URI to resolve all relative
  /// URI references against.
  ///
  /// The `Packages` object allows resolving package: URIs and writing
  /// the mapping back to a file or string.
  /// The [packageMapping] will contain a simple mapping from package name
  /// to package location.
  static Packages parse(String source, Uri baseLocation) {
    int index = 0;
    Map<String, Uri> result = <String, Uri>{};
    while (index < source.length) {
      bool isComment = false;
      int start = index;
      int eqIndex = -1;
      int end = source.length;
      int char = source.codeUnitAt(index++);
      if (char == _CR || char == _NL) {
        continue;
      }
      if (char == _EQUALS) {
        throw new FormatException("Missing package name", source, index - 1);
      }
      isComment = char == _NUMBER_SIGN;
      while (index < source.length) {
        char = source.codeUnitAt(index++);
        if (char == _EQUALS && eqIndex < 0) {
          eqIndex = index - 1;
        } else if (char == _NL || char == _CR) {
          end = index - 1;
          break;
        }
      }
      if (isComment) continue;
      if (eqIndex < 0) {
        throw new FormatException("No '=' on line", source, index - 1);
      }
      _checkIdentifier(source, start, eqIndex);
      var packageName = source.substring(start, eqIndex);

      var packageLocation = Uri.parse(source, eqIndex + 1, end);
      if (!packageLocation.path.endsWith('/')) {
        packageLocation =
            packageLocation.replace(path: packageLocation.path + "/");
      }
      packageLocation = baseLocation.resolveUri(packageLocation);
      if (result.containsKey(packageName)) {
        throw new FormatException(
            "Same package name occured twice.", source, start);
      }
      result[packageName] = packageLocation;
    }
    return new Packages(result);
  }

  /**
   * Writes the mapping to a [StringSink].
   *
   * If [comment] is provided, the output will contain this comment
   * with `#` in front of each line.
   *
   * If [baseUri] is provided, package locations will be made relative
   * to the base URI, if possible, before writing.
   */
  void write(StringSink output, {Uri baseUri, String comment}) {
    if (baseUri != null && !baseUri.isAbsolute) {
      throw new ArgumentError.value(baseUri, "baseUri", "Must be absolute");
    }

    if (comment != null) {
      for (var commentLine in comment.split('\n')) {
        output.write('#');
        output.writeln(commentLine);
      }
    } else {
      output.write("# generated by package:packagecfg at ");
      output.write(new DateTime.now());
      output.writeln();
    }

    packageMapping.forEach((String packageName, Uri uri) {
      // Validate packageName.
      _checkIdentifier(packageName, 0, packageName.length);
      output.write(packageName);

      output.write('=');

      // If baseUri provided, make uri relative.
      if (baseUri != null) {
        uri = relativize(uri, baseUri);
      }
      output.write(uri);
      if (!uri.path.endsWith('/')) {
        output.write('/');
      }
      output.writeln();
    });
  }

  String toString() {
    StringBuffer buffer = new StringBuffer();
    write(buffer);
    return buffer.toString();
  }

  static Uri relativize(Uri uri, Uri baseUri) {
    if (uri.hasQuery || uri.hasFragment) {
      uri = new Uri(
          scheme: uri.scheme,
          userInfo: uri.hasAuthority ? uri.userInfo : null,
          host: uri.hasAuthority ? uri.host : null,
          port: uri.hasAuthority ? uri.port : null,
          path: uri.path);
    }
    if (!baseUri.isAbsolute) {
      throw new ArgumentError("Base uri '$baseUri' must be absolute.");
    }
    // Already relative.
    if (!uri.isAbsolute) return uri;

    if (baseUri.scheme.toLowerCase() != uri.scheme.toLowerCase()) {
      return uri;
    }
    // If authority differs, we could remove the scheme, but it's not worth it.
    if (uri.hasAuthority != baseUri.hasAuthority) return uri;
    if (uri.hasAuthority) {
      if (uri.userInfo != baseUri.userInfo ||
          uri.host.toLowerCase() != baseUri.host.toLowerCase() ||
          uri.port != baseUri.port) {
        return uri;
      }
    }

    baseUri = _normalizePath(baseUri);
    List<String> base = baseUri.pathSegments.toList();
    if (base.isNotEmpty) {
      base = new List<String>.from(base)..removeLast();
    }
    uri = _normalizePath(uri);
    List<String> target = uri.pathSegments.toList();
    int index = 0;
    while (index < base.length && index < target.length) {
      if (base[index] != target[index]) {
        break;
      }
      index++;
    }
    if (index == base.length) {
      return new Uri(path: target.skip(index).join('/'));
    } else if (index > 0) {
      return new Uri(
          path: '../' * (base.length - index) + target.skip(index).join('/'));
    } else {
      return uri;
    }
  }

  static bool _checkIdentifier(String string, int start, int end) {
    const int a = 0x61;
    const int z = 0x7a;
    const int _ = 0x5f;
    const int $ = 0x24;
    if (start == end) return false;
    for (int i = start; i < end; i++) {
      var char = string.codeUnitAt(i);
      if (char == _ || char == $) continue;
      if ((char ^ 0x30) <= 9 && i > 0) continue;
      char |= 0x20; // Lower-case letters.
      if (char >= a && char <= z) continue;
      throw new FormatException("Not an identifier", string, i);
    }
    return true;
  }
}
