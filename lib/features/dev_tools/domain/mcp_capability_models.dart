enum McpCapabilityTier { app, local, lan }

class McpToolInterface {
  const McpToolInterface({
    required this.name,
    required this.title,
    required this.description,
    required this.inputSchema,
    this.risk = '',
    this.annotations = const <String, Object?>{},
  });

  final String name;
  final String title;
  final String description;
  final Map<String, Object?> inputSchema;
  final String risk;
  final Map<String, Object?> annotations;

  factory McpToolInterface.fromJson(Map<Object?, Object?> json) {
    final Object? rawSchema = json['inputSchema'];
    return McpToolInterface(
      name: '${json['name'] ?? json['id'] ?? ''}'.trim(),
      title:
          '${json['title'] ?? json['displayName'] ?? json['name'] ?? json['id'] ?? ''}'
              .trim(),
      description: '${json['description'] ?? ''}'.trim(),
      risk: '${json['risk'] ?? ''}'.trim(),
      annotations: json['annotations'] is Map
          ? Map<String, Object?>.from(json['annotations']! as Map)
          : const <String, Object?>{},
      inputSchema: rawSchema is Map
          ? Map<String, Object?>.from(rawSchema)
          : const <String, Object?>{'type': 'object'},
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'title': title,
    'description': description,
    'inputSchema': inputSchema,
    if (risk.isNotEmpty) 'risk': risk,
    if (annotations.isNotEmpty) 'annotations': annotations,
  };
}

class McpDeviceCapability {
  const McpDeviceCapability({
    required this.id,
    required this.name,
    required this.appId,
    required this.appVersion,
    required this.tier,
    required this.transport,
    required this.endpoint,
    required this.tools,
    required this.lastUpdated,
    this.online = true,
    this.catalogRevision = '',
    this.hardwareCode = '',
    this.launchArguments = const <String>[],
  });

  final String id;
  final String name;
  final String appId;
  final String appVersion;
  final McpCapabilityTier tier;
  final String transport;
  final String endpoint;
  final List<McpToolInterface> tools;
  final DateTime lastUpdated;
  final bool online;
  final String catalogRevision;
  final String hardwareCode;
  final List<String> launchArguments;

  bool get callable =>
      tier == McpCapabilityTier.app ||
      (tier == McpCapabilityTier.local &&
          transport == 'stdio' &&
          endpoint.isNotEmpty &&
          tools.isNotEmpty) ||
      (tier == McpCapabilityTier.lan &&
          transport == 'https-streamable-http' &&
          tools.isNotEmpty);
}

class McpCapabilitySnapshot {
  const McpCapabilitySnapshot({
    required this.version,
    required this.app,
    required this.local,
    required this.lan,
    required this.updatedAt,
  });

  final int version;
  final List<McpDeviceCapability> app;
  final List<McpDeviceCapability> local;
  final List<McpDeviceCapability> lan;
  final DateTime updatedAt;

  List<McpDeviceCapability> get inHarnessSearchOrder => <McpDeviceCapability>[
    ...app,
    ...local,
    ...lan,
  ];
}
