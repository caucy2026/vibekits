enum McpCapabilityTier { app, local, lan }

enum McpNodeState { idle, busy, saturated, draining, error }

class McpNodeRuntime {
  const McpNodeRuntime({
    required this.state,
    required this.capacity,
    required this.inFlight,
    required this.queueDepth,
    required this.availableSlots,
    required this.loadRevision,
    required this.oldestTaskAgeMs,
    required this.draining,
    required this.acceptingReservations,
  });

  const McpNodeRuntime.unknown()
    : state = McpNodeState.error,
      capacity = 0,
      inFlight = 0,
      queueDepth = 0,
      availableSlots = 0,
      loadRevision = 0,
      oldestTaskAgeMs = 0,
      draining = false,
      acceptingReservations = false;

  final McpNodeState state;
  final int capacity;
  final int inFlight;
  final int queueDepth;
  final int availableSlots;
  final int loadRevision;
  final int oldestTaskAgeMs;
  final bool draining;
  final bool acceptingReservations;

  bool get valid =>
      capacity >= 1 &&
      inFlight >= 0 &&
      inFlight <= capacity &&
      queueDepth >= 0 &&
      availableSlots >= 0 &&
      availableSlots <= capacity &&
      availableSlots <= capacity - inFlight &&
      loadRevision >= 1 &&
      oldestTaskAgeMs >= 0;

  bool get schedulable =>
      valid &&
      acceptingReservations &&
      !draining &&
      state != McpNodeState.error &&
      state != McpNodeState.draining &&
      availableSlots > 0;

  factory McpNodeRuntime.fromJson(Object? value) {
    if (value is! Map) return const McpNodeRuntime.unknown();
    final String stateName = '${value['state'] ?? ''}'.trim();
    final McpNodeState? state = McpNodeState.values
        .where((McpNodeState item) => item.name == stateName)
        .firstOrNull;
    int integer(String key) => value[key] is int ? value[key]! as int : -1;
    final McpNodeRuntime runtime = McpNodeRuntime(
      state: state ?? McpNodeState.error,
      capacity: integer('capacity'),
      inFlight: integer('inFlight'),
      queueDepth: integer('queueDepth'),
      availableSlots: integer('availableSlots'),
      loadRevision: integer('loadRevision'),
      oldestTaskAgeMs: integer('oldestTaskAgeMs'),
      draining: value['draining'] == true,
      acceptingReservations: value['acceptingReservations'] == true,
    );
    return runtime.valid ? runtime : const McpNodeRuntime.unknown();
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'state': state.name,
    'capacity': capacity,
    'inFlight': inFlight,
    'queueDepth': queueDepth,
    'availableSlots': availableSlots,
    'loadRevision': loadRevision,
    'oldestTaskAgeMs': oldestTaskAgeMs,
    'draining': draining,
    'acceptingReservations': acceptingReservations,
  };
}

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
      risk: json['risk'] is Map
          ? '${(json['risk']! as Map)['level'] ?? ''}'.trim()
          : '${json['risk'] ?? ''}'.trim(),
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
    this.runtime = const McpNodeRuntime.unknown(),
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
  final McpNodeRuntime runtime;

  bool get supportsSchedulingTools {
    final Set<String> names = tools
        .map((McpToolInterface tool) => tool.name)
        .toSet();
    return const <String>{
      'lmcp.node.status',
      'lmcp.capacity.reserve',
      'lmcp.capacity.renew',
      'lmcp.capacity.release',
    }.every(names.contains);
  }

  bool get schedulable =>
      callable && runtime.schedulable && supportsSchedulingTools;

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
