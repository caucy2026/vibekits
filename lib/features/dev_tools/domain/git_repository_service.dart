import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

class GitRepositorySnapshot {
  const GitRepositorySnapshot({
    required this.root,
    required this.branch,
    required this.status,
    required this.diff,
    required this.log,
  });

  final String root;
  final String branch;
  final String status;
  final String diff;
  final String log;
}

class GitReferenceComparison {
  const GitReferenceComparison({
    required this.root,
    required this.baseRef,
    required this.targetRef,
    required this.baseCommit,
    required this.targetCommit,
    required this.summary,
    required this.changedFiles,
    required this.diff,
  });

  final String root;
  final String baseRef;
  final String targetRef;
  final String baseCommit;
  final String targetCommit;
  final String summary;
  final String changedFiles;
  final String diff;
}

class GitRemoteReference {
  const GitRemoteReference({required this.sha, required this.ref});

  final String sha;
  final String ref;

  Map<String, Object?> toJson() => <String, Object?>{'sha': sha, 'ref': ref};
}

class GitRemoteFileResult {
  const GitRemoteFileResult({
    required this.remoteUrl,
    required this.ref,
    required this.path,
    required this.commitSha,
    required this.content,
    required this.byteLength,
  });

  final String remoteUrl;
  final String ref;
  final String path;
  final String commitSha;
  final String content;
  final int byteLength;

  Map<String, Object?> toJson() => <String, Object?>{
    'remoteUrl': remoteUrl,
    'ref': ref,
    'path': path,
    'commitSha': commitSha,
    'content': content,
    'byteLength': byteLength,
    'evidenceSource': 'bundled-git-fetch-show',
  };
}

class GitMinimalCloneResult {
  const GitMinimalCloneResult({
    required this.remoteUrl,
    required this.destination,
    required this.ref,
    required this.commitSha,
    required this.depth,
  });

  final String remoteUrl;
  final String destination;
  final String ref;
  final String commitSha;
  final int depth;

  Map<String, Object?> toJson() => <String, Object?>{
    'remoteUrl': remoteUrl,
    'destination': destination,
    'ref': ref,
    'commitSha': commitSha,
    'depth': depth,
    'fullRepositorySync': false,
    'evidenceSource': 'bundled-git-clone',
  };
}

class GitBackupPreview {
  const GitBackupPreview({
    required this.id,
    required this.repositoryRoot,
    required this.repositoryStateDigest,
    required this.currentBranch,
    required this.remoteId,
    required this.remoteUrl,
    required this.targetBranch,
    required this.includedPaths,
    required this.stagedCount,
    required this.unstagedCount,
    required this.untrackedCount,
    required this.blockers,
    required this.warnings,
    required this.remoteReachable,
    required this.expiresAt,
    this.commitSha,
  });

  final String id;
  final String repositoryRoot;
  final String repositoryStateDigest;
  final String currentBranch;
  final String remoteId;
  final String remoteUrl;
  final String targetBranch;
  final List<String> includedPaths;
  final int stagedCount;
  final int unstagedCount;
  final int untrackedCount;
  final List<String> blockers;
  final List<String> warnings;
  final bool remoteReachable;
  final DateTime expiresAt;
  final String? commitSha;

  Map<String, Object?> toJson() => <String, Object?>{
    'previewId': id,
    'repositoryRoot': repositoryRoot,
    'repositoryStateDigest': repositoryStateDigest,
    'currentBranch': currentBranch,
    'remoteId': remoteId,
    'remoteUrl': remoteUrl,
    'targetBranch': targetBranch,
    'includedPaths': includedPaths,
    'stagedCount': stagedCount,
    'unstagedCount': unstagedCount,
    'untrackedCount': untrackedCount,
    'blockers': blockers,
    'warnings': warnings,
    'remoteReachable': remoteReachable,
    'expiresAt': expiresAt.toUtc().toIso8601String(),
    if (commitSha != null) 'commitSha': commitSha,
  };
}

class GitBackupCommitResult {
  const GitBackupCommitResult({
    required this.previewId,
    required this.commitSha,
    required this.targetBranch,
    required this.pathCount,
  });

  final String previewId;
  final String commitSha;
  final String targetBranch;
  final int pathCount;

  Map<String, Object?> toJson() => <String, Object?>{
    'previewId': previewId,
    'commitSha': commitSha,
    'targetBranch': targetBranch,
    'pathCount': pathCount,
    'pushRequired': true,
  };
}

class GitBackupPushResult {
  const GitBackupPushResult({
    required this.previewId,
    required this.remoteId,
    required this.targetBranch,
    required this.localCommitSha,
    required this.remoteCommitSha,
    required this.verified,
  });

  final String previewId;
  final String remoteId;
  final String targetBranch;
  final String localCommitSha;
  final String remoteCommitSha;
  final bool verified;

  Map<String, Object?> toJson() => <String, Object?>{
    'previewId': previewId,
    'remoteId': remoteId,
    'targetBranch': targetBranch,
    'localCommitSha': localCommitSha,
    'remoteCommitSha': remoteCommitSha,
    'verified': verified,
  };
}

class _GitBackupPlanState {
  _GitBackupPlanState(this.preview);

  GitBackupPreview preview;
  List<String>? committedPaths;
  String? commitMessage;
}

abstract final class GitRepositoryService {
  static const int _maxOutputBytes = 2 * 1024 * 1024;
  static const int _largeFileWarningBytes = 50 * 1024 * 1024;
  static const Duration _backupPlanLifetime = Duration(minutes: 15);
  static final Map<String, _GitBackupPlanState> _backupPlans =
      <String, _GitBackupPlanState>{};

  static String get bundledExecutable => _resolveGitExecutable();

  static Future<List<GitRemoteReference>> listRemoteReferences(
    String remoteUrl, {
    String? pattern,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final String remote = _requiredRemoteUrl(remoteUrl);
    final String refPattern = (pattern ?? '').trim();
    if (refPattern.startsWith('-')) {
      throw const FormatException('引用匹配不能以 - 开头');
    }
    final String output = await _git(Directory.systemTemp.path, <String>[
      'ls-remote',
      remote,
      if (refPattern.isNotEmpty) refPattern,
    ], timeout: timeout);
    return <GitRemoteReference>[
      for (final String line in output.split('\n'))
        if (line.trim().isNotEmpty) _parseRemoteReference(line),
    ];
  }

  static Future<GitRemoteFileResult> readRemoteTextFile(
    String remoteUrl, {
    required String ref,
    required String path,
    int maxBytes = 2 * 1024 * 1024,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final String remote = _requiredRemoteUrl(remoteUrl);
    final String remoteRef = _requiredRef(ref, '远端版本');
    final String relativePath = _requiredRemotePath(path);
    final int boundedMaxBytes = maxBytes.clamp(1, _maxOutputBytes);
    final Directory temporary = await Directory.systemTemp.createTemp(
      'vibekits-git-read-',
    );
    try {
      await _git(temporary.path, <String>['init', '--bare']);
      await _git(temporary.path, <String>[
        'fetch',
        '--depth=1',
        '--no-tags',
        remote,
        remoteRef,
      ], timeout: timeout);
      final String commitSha = (await _git(temporary.path, <String>[
        'rev-parse',
        '--verify',
        'FETCH_HEAD^{commit}',
      ])).trim();
      final String content = await _git(temporary.path, <String>[
        'show',
        'FETCH_HEAD:$relativePath',
      ], maxOutputBytes: boundedMaxBytes);
      return GitRemoteFileResult(
        remoteUrl: _redactRemoteUrl(remote),
        ref: remoteRef,
        path: relativePath,
        commitSha: commitSha,
        content: content,
        byteLength: utf8.encode(content).length,
      );
    } finally {
      if (temporary.existsSync()) {
        await temporary.delete(recursive: true);
      }
    }
  }

  static Future<GitMinimalCloneResult> cloneMinimal(
    String remoteUrl, {
    required String destination,
    String ref = 'master',
    int depth = 1,
    Duration timeout = const Duration(minutes: 5),
  }) async {
    final String remote = _requiredRemoteUrl(remoteUrl);
    final String remoteRef = _requiredRef(ref, '远端版本');
    final int boundedDepth = depth.clamp(1, 100);
    final Directory target = Directory(destination.trim()).absolute;
    if (destination.trim().isEmpty) {
      throw const FormatException('请输入独立目标目录');
    }
    final FileSystemEntityType existingType = FileSystemEntity.typeSync(
      target.path,
      followLinks: false,
    );
    if (existingType != FileSystemEntityType.notFound) {
      throw const FormatException('目标目录必须不存在，避免覆盖已有文件');
    }
    final Directory parent = target.parent;
    if (!parent.existsSync()) await parent.create(recursive: true);
    try {
      await _git(parent.path, <String>[
        'clone',
        '--depth=$boundedDepth',
        '--no-tags',
        '--single-branch',
        '--branch',
        remoteRef,
        remote,
        target.path,
      ], timeout: timeout);
      final String commitSha = (await _git(target.path, <String>[
        'rev-parse',
        '--verify',
        'HEAD^{commit}',
      ])).trim();
      return GitMinimalCloneResult(
        remoteUrl: _redactRemoteUrl(remote),
        destination: target.path,
        ref: remoteRef,
        commitSha: commitSha,
        depth: boundedDepth,
      );
    } catch (_) {
      if (target.existsSync()) await target.delete(recursive: true);
      rethrow;
    }
  }

  static Future<GitRepositorySnapshot> inspect(String directory) async {
    final String path = directory.trim();
    if (FileSystemEntity.typeSync(path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw const FormatException('请选择存在的项目目录');
    }
    final String root = (await _git(path, <String>[
      'rev-parse',
      '--show-toplevel',
    ])).trim();
    final String status = await _git(root, <String>[
      'status',
      '--porcelain=v1',
      '--branch',
      '--untracked-files=all',
    ]);
    final String firstLine = status.split('\n').firstOrNull ?? '';
    final String branch = firstLine.startsWith('## ')
        ? firstLine.substring(3).trim()
        : 'detached / unknown';
    final List<String> diffs = await Future.wait(<Future<String>>[
      _git(root, <String>[
        'diff',
        '--no-ext-diff',
        '--no-textconv',
        '--unified=3',
        '--',
      ]),
      _git(root, <String>[
        'diff',
        '--cached',
        '--no-ext-diff',
        '--no-textconv',
        '--unified=3',
        '--',
      ]),
    ]);
    String log;
    try {
      log = await _git(root, <String>[
        'log',
        '-n',
        '30',
        '--date=short',
        '--pretty=format:%h%x09%ad%x09%s',
      ]);
    } on FormatException catch (error) {
      if (error.message.contains('does not have any commits yet')) {
        log = '仓库尚无提交';
      } else {
        rethrow;
      }
    }
    final String unstaged = diffs[0].trim();
    final String staged = diffs[1].trim();
    final String combinedDiff = <String>[
      if (staged.isNotEmpty) '=== 已暂存 ===\n$staged',
      if (unstaged.isNotEmpty) '=== 未暂存 ===\n$unstaged',
    ].join('\n\n');
    return GitRepositorySnapshot(
      root: root,
      branch: branch,
      status: status.trim().isEmpty ? '工作区干净' : status.trim(),
      diff: combinedDiff.isEmpty ? '没有文本差异' : combinedDiff,
      log: log.trim().isEmpty ? '仓库尚无提交' : log.trim(),
    );
  }

  static Future<GitReferenceComparison> compareRefs(
    String directory, {
    required String baseRef,
    required String targetRef,
  }) async {
    final String root = await _repositoryRoot(directory);
    final String base = _requiredRef(baseRef, '基准版本');
    final String target = _requiredRef(targetRef, '目标版本');
    final List<String> commits = await Future.wait(<Future<String>>[
      _git(root, <String>['rev-parse', '--verify', '$base^{commit}']),
      _git(root, <String>['rev-parse', '--verify', '$target^{commit}']),
    ]);
    final List<String> details = await Future.wait(<Future<String>>[
      _git(root, <String>[
        'diff',
        '--stat',
        '--no-ext-diff',
        base,
        target,
        '--',
      ]),
      _git(root, <String>[
        'diff',
        '--name-status',
        '--no-renames',
        '--no-ext-diff',
        base,
        target,
        '--',
      ]),
      _git(root, <String>[
        'diff',
        '--no-renames',
        '--no-ext-diff',
        '--no-textconv',
        '--unified=3',
        base,
        target,
        '--',
      ]),
    ]);
    return GitReferenceComparison(
      root: root,
      baseRef: base,
      targetRef: target,
      baseCommit: commits[0].trim(),
      targetCommit: commits[1].trim(),
      summary: details[0].trim().isEmpty ? '两个版本没有差异' : details[0].trim(),
      changedFiles: details[1].trim().isEmpty ? '没有变化的文件' : details[1].trim(),
      diff: details[2].trim().isEmpty ? '没有文本差异' : details[2].trim(),
    );
  }

  /// Creates a local safety branch without switching the current checkout.
  static Future<String> createLocalBranch(
    String directory, {
    required String name,
    String startPoint = 'HEAD',
  }) async {
    final String root = await _repositoryRoot(directory);
    final String branch = name.trim();
    if (branch.isEmpty) throw const FormatException('请输入本地分支名称');
    await _git(root, <String>['check-ref-format', '--branch', branch]);
    final String start = _requiredRef(startPoint, '起点版本');
    await _git(root, <String>['rev-parse', '--verify', '$start^{commit}']);
    await _git(root, <String>['branch', '--', branch, start]);
    return branch;
  }

  static Future<GitBackupPreview> previewBackup(
    String directory, {
    required String remoteId,
    String? deviceLabel,
    DateTime? now,
  }) async {
    final DateTime createdAt = now ?? DateTime.now();
    _pruneBackupPlans(createdAt);
    final String root = await _repositoryRoot(directory);
    final String remote = _requiredRemoteId(remoteId);
    final String remoteUrl = (await _git(root, <String>[
      'remote',
      'get-url',
      '--',
      remote,
    ])).trim();
    final String porcelain = await _git(root, <String>[
      'status',
      '--porcelain=v1',
      '-z',
      '--untracked-files=all',
    ]);
    final List<_GitStatusPath> changed = _parsePorcelain(porcelain);
    if (changed.isEmpty) throw const FormatException('工作区没有可备份的变更');
    final List<String> paths =
        changed
            .map((_GitStatusPath item) => item.path)
            .toSet()
            .toList(growable: false)
          ..sort();
    final Map<String, List<String>> safety = await Isolate.run(
      () => _inspectBackupPaths(root, paths),
    );
    final List<String> blockers = safety['blockers'] ?? <String>[];
    final List<String> warnings = safety['warnings'] ?? <String>[];
    final String branch = (await _git(root, <String>[
      'branch',
      '--show-current',
    ])).trim();
    final String project = _safeBranchPart(
      root
          .split(Platform.pathSeparator)
          .where((String part) => part.isNotEmpty)
          .last,
    );
    final String device = _safeBranchPart(
      (deviceLabel ?? Platform.localHostname).trim(),
    );
    final String date =
        '${createdAt.year.toString().padLeft(4, '0')}'
        '${createdAt.month.toString().padLeft(2, '0')}'
        '${createdAt.day.toString().padLeft(2, '0')}';
    bool remoteReachable = false;
    try {
      await _git(root, <String>[
        'ls-remote',
        '--heads',
        remote,
      ], timeout: const Duration(seconds: 20));
      remoteReachable = true;
    } on Object catch (error) {
      warnings.add('远端当前不可达：${_safeGitError(error)}；本地提交后可重试 push');
    }
    final String digest = await Isolate.run(
      () => _computeBackupStateDigest(root, porcelain, paths),
    );
    final String id = _randomPlanId();
    final GitBackupPreview preview = GitBackupPreview(
      id: id,
      repositoryRoot: root,
      repositoryStateDigest: digest,
      currentBranch: branch.isEmpty ? 'detached' : branch,
      remoteId: remote,
      remoteUrl: _redactRemoteUrl(remoteUrl),
      targetBranch: 'backup/$device/$project/$date',
      includedPaths: List<String>.unmodifiable(paths),
      stagedCount: changed.where((_GitStatusPath item) => item.staged).length,
      unstagedCount: changed
          .where((_GitStatusPath item) => item.unstaged)
          .length,
      untrackedCount: changed
          .where((_GitStatusPath item) => item.untracked)
          .length,
      blockers: List<String>.unmodifiable(blockers),
      warnings: List<String>.unmodifiable(warnings),
      remoteReachable: remoteReachable,
      expiresAt: createdAt.add(_backupPlanLifetime),
    );
    _backupPlans[id] = _GitBackupPlanState(preview);
    return preview;
  }

  static Future<GitBackupCommitResult> commitBackup({
    required String previewId,
    required List<String> includedPaths,
    required String message,
    DateTime? now,
  }) async {
    final _GitBackupPlanState plan = await _validatedBackupPlan(
      previewId,
      now: now,
      requireUnchangedState: true,
    );
    final String commitMessage = message.trim();
    if (commitMessage.isEmpty || commitMessage.length > 200) {
      throw const FormatException('提交说明必须为 1～200 个字符');
    }
    final Set<String> allowed = plan.preview.includedPaths.toSet();
    final List<String> selected = includedPaths.toSet().toList()..sort();
    if (selected.isEmpty ||
        selected.any((String path) => !allowed.contains(path))) {
      throw const FormatException('提交文件必须是 preview 返回的非空文件子集');
    }
    if (plan.preview.blockers.isNotEmpty) {
      throw FormatException('备份被安全检查阻断：${plan.preview.blockers.join('；')}');
    }
    final Map<String, List<String>> currentSafety = await Isolate.run(
      () => _inspectBackupPaths(plan.preview.repositoryRoot, selected),
    );
    final List<String> currentBlockers =
        currentSafety['blockers'] ?? const <String>[];
    if (currentBlockers.isNotEmpty) {
      throw FormatException('提交前安全复查阻断：${currentBlockers.join('；')}');
    }
    if (plan.preview.commitSha != null) {
      if (!_sameStrings(plan.committedPaths ?? const <String>[], selected) ||
          plan.commitMessage != commitMessage) {
        throw const FormatException('该 preview 已生成不同的提交；请重新预览');
      }
      return GitBackupCommitResult(
        previewId: previewId,
        commitSha: plan.preview.commitSha!,
        targetBranch: plan.preview.targetBranch,
        pathCount: selected.length,
      );
    }
    final String sha = await _createDetachedBackupCommit(
      repositoryRoot: plan.preview.repositoryRoot,
      selectedPaths: selected,
      message: commitMessage,
    );
    plan
      ..committedPaths = List<String>.unmodifiable(selected)
      ..commitMessage = commitMessage;
    plan.preview = GitBackupPreview(
      id: plan.preview.id,
      repositoryRoot: plan.preview.repositoryRoot,
      repositoryStateDigest: plan.preview.repositoryStateDigest,
      currentBranch: plan.preview.currentBranch,
      remoteId: plan.preview.remoteId,
      remoteUrl: plan.preview.remoteUrl,
      targetBranch: plan.preview.targetBranch,
      includedPaths: plan.preview.includedPaths,
      stagedCount: plan.preview.stagedCount,
      unstagedCount: plan.preview.unstagedCount,
      untrackedCount: plan.preview.untrackedCount,
      blockers: plan.preview.blockers,
      warnings: plan.preview.warnings,
      remoteReachable: plan.preview.remoteReachable,
      expiresAt: plan.preview.expiresAt,
      commitSha: sha,
    );
    return GitBackupCommitResult(
      previewId: previewId,
      commitSha: sha,
      targetBranch: plan.preview.targetBranch,
      pathCount: selected.length,
    );
  }

  static Future<GitBackupPushResult> pushBackup({
    required String previewId,
    required String commitSha,
    DateTime? now,
  }) async {
    final _GitBackupPlanState plan = await _validatedBackupPlan(
      previewId,
      now: now,
      requireUnchangedState: false,
    );
    final String expectedSha = plan.preview.commitSha ?? '';
    if (expectedSha.isEmpty || commitSha.trim() != expectedSha) {
      throw const FormatException('push 只接受本 preview 已生成的 commit SHA');
    }
    final String ref = 'refs/heads/${plan.preview.targetBranch}';
    await _git(plan.preview.repositoryRoot, <String>[
      'push',
      '--porcelain',
      plan.preview.remoteId,
      '$expectedSha:$ref',
    ], timeout: const Duration(minutes: 3));
    final String remoteSha = await verifyRemoteRef(
      plan.preview.repositoryRoot,
      remoteId: plan.preview.remoteId,
      targetBranch: plan.preview.targetBranch,
    );
    return GitBackupPushResult(
      previewId: previewId,
      remoteId: plan.preview.remoteId,
      targetBranch: plan.preview.targetBranch,
      localCommitSha: expectedSha,
      remoteCommitSha: remoteSha,
      verified: remoteSha == expectedSha,
    );
  }

  static Future<String> verifyRemoteRef(
    String directory, {
    required String remoteId,
    required String targetBranch,
  }) async {
    final String root = await _repositoryRoot(directory);
    final String remote = _requiredRemoteId(remoteId);
    final String branch = _requiredBackupBranch(targetBranch);
    final String output = (await _git(root, <String>[
      'ls-remote',
      '--heads',
      remote,
      'refs/heads/$branch',
    ], timeout: const Duration(seconds: 30))).trim();
    if (output.isEmpty) throw const FormatException('远端未找到目标备份分支');
    final String sha = output.split(RegExp(r'\s+')).first;
    if (!RegExp(r'^[0-9a-fA-F]{40,64}$').hasMatch(sha)) {
      throw const FormatException('远端返回了无效 commit SHA');
    }
    return sha.toLowerCase();
  }

  static Future<_GitBackupPlanState> _validatedBackupPlan(
    String id, {
    DateTime? now,
    required bool requireUnchangedState,
  }) async {
    final DateTime current = now ?? DateTime.now();
    _pruneBackupPlans(current);
    final _GitBackupPlanState? plan = _backupPlans[id.trim()];
    if (plan == null) throw const FormatException('preview 不存在或已过期，请重新预览');
    if (requireUnchangedState) {
      final String porcelain = await _git(plan.preview.repositoryRoot, <String>[
        'status',
        '--porcelain=v1',
        '-z',
        '--untracked-files=all',
      ]);
      final String digest = await Isolate.run(
        () => _computeBackupStateDigest(
          plan.preview.repositoryRoot,
          porcelain,
          plan.preview.includedPaths,
        ),
      );
      if (digest != plan.preview.repositoryStateDigest) {
        throw const FormatException('仓库状态已变化，旧 preview 已失效，请重新预览');
      }
    }
    return plan;
  }

  static void _pruneBackupPlans(DateTime now) {
    _backupPlans.removeWhere(
      (String _, _GitBackupPlanState value) =>
          !value.preview.expiresAt.isAfter(now),
    );
  }

  static void _inspectBackupPath(
    String root,
    String relativePath,
    List<String> blockers,
    List<String> warnings,
  ) {
    final String normalized = relativePath.replaceAll('\\', '/');
    final String lower = normalized.toLowerCase();
    final List<String> segments = lower.split('/');
    final String name = segments.last;
    if (_isSecretFileName(name, lower)) {
      blockers.add('$relativePath：疑似凭据、私钥或环境秘密文件');
      return;
    }
    if (segments.any(
      const <String>{
        'build',
        '.dart_tool',
        'node_modules',
        '.gradle',
        'dist',
        'target',
      }.contains,
    )) {
      warnings.add('$relativePath：疑似构建产物或依赖目录');
    }
    final File file = File(
      '$root${Platform.pathSeparator}${relativePath.replaceAll('/', Platform.pathSeparator)}',
    );
    if (!file.existsSync()) return;
    final int length = file.lengthSync();
    if (length > _largeFileWarningBytes) {
      warnings.add('$relativePath：大文件 ${_formatBytes(length)}');
    }
    if (length > 1024 * 1024 || _looksBinaryExtension(name)) return;
    try {
      final String decoded = file.readAsStringSync();
      final String content = decoded.substring(
        0,
        decoded.length.clamp(0, 1024 * 1024),
      );
      if (_containsSecret(content)) {
        blockers.add('$relativePath：内容疑似包含 Token、密码或私钥');
      }
    } on Object {
      // Binary or undecodable content is handled through filename/size policy.
    }
  }

  static Map<String, List<String>> _inspectBackupPaths(
    String root,
    List<String> paths,
  ) {
    final List<String> blockers = <String>[];
    final List<String> warnings = <String>[];
    for (final String relativePath in paths) {
      _inspectBackupPath(root, relativePath, blockers, warnings);
    }
    return <String, List<String>>{'blockers': blockers, 'warnings': warnings};
  }

  static Future<String> _computeBackupStateDigest(
    String root,
    String porcelain,
    List<String> paths,
  ) async {
    final List<Map<String, Object?>> entries = <Map<String, Object?>>[];
    for (final String relativePath in paths) {
      final String safePath = _safeRelativeBackupPath(relativePath);
      final String absolutePath =
          '$root${Platform.pathSeparator}${safePath.replaceAll('/', Platform.pathSeparator)}';
      final FileSystemEntityType type = FileSystemEntity.typeSync(
        absolutePath,
        followLinks: false,
      );
      if (type == FileSystemEntityType.notFound) {
        entries.add(<String, Object?>{'path': safePath, 'type': 'missing'});
        continue;
      }
      if (type == FileSystemEntityType.link) {
        entries.add(<String, Object?>{'path': safePath, 'type': 'link'});
        continue;
      }
      if (type != FileSystemEntityType.file) {
        entries.add(<String, Object?>{
          'path': safePath,
          'type': type.toString(),
        });
        continue;
      }
      final File file = File(absolutePath);
      final Digest digest = await sha256.bind(file.openRead()).first;
      entries.add(<String, Object?>{
        'path': safePath,
        'type': 'file',
        'length': await file.length(),
        'sha256': digest.toString(),
      });
    }
    return sha256
        .convert(
          utf8.encode(
            jsonEncode(<String, Object?>{
              'porcelain': porcelain,
              'entries': entries,
            }),
          ),
        )
        .toString();
  }

  static Future<String> _createDetachedBackupCommit({
    required String repositoryRoot,
    required List<String> selectedPaths,
    required String message,
  }) async {
    final String parent = (await _git(repositoryRoot, <String>[
      'rev-parse',
      '--verify',
      'HEAD^{commit}',
    ])).trim();
    final Directory temporary = Directory.systemTemp.createTempSync(
      'vibekits_git_backup_',
    );
    temporary.deleteSync();
    bool worktreeRegistered = false;
    try {
      await _git(repositoryRoot, <String>[
        'worktree',
        'add',
        '--detach',
        temporary.path,
        parent,
      ], timeout: const Duration(minutes: 2));
      worktreeRegistered = true;
      for (final String relativePath in selectedPaths) {
        final String safePath = _safeRelativeBackupPath(relativePath);
        final String platformPath = safePath.replaceAll(
          '/',
          Platform.pathSeparator,
        );
        final String sourcePath =
            '$repositoryRoot${Platform.pathSeparator}$platformPath';
        final String targetPath =
            '${temporary.path}${Platform.pathSeparator}$platformPath';
        final FileSystemEntityType sourceType = FileSystemEntity.typeSync(
          sourcePath,
          followLinks: false,
        );
        if (sourceType == FileSystemEntityType.link) {
          throw FormatException('$safePath：备份不接受符号链接或重解析点');
        }
        if (sourceType == FileSystemEntityType.directory) {
          throw FormatException('$safePath：备份文件集合不能包含目录');
        }
        if (sourceType == FileSystemEntityType.notFound) {
          final FileSystemEntityType targetType = FileSystemEntity.typeSync(
            targetPath,
            followLinks: false,
          );
          if (targetType == FileSystemEntityType.file) {
            File(targetPath).deleteSync();
          } else if (targetType != FileSystemEntityType.notFound) {
            throw FormatException('$safePath：删除目标不是普通文件');
          }
          continue;
        }
        if (sourceType != FileSystemEntityType.file) {
          throw FormatException('$safePath：只允许备份普通文件');
        }
        final File target = File(targetPath);
        target.parent.createSync(recursive: true);
        await File(sourcePath).copy(target.path);
      }
      await _git(temporary.path, <String>[
        'add',
        '--all',
        '--',
        ...selectedPaths,
      ]);
      await _git(temporary.path, <String>[
        'commit',
        '-m',
        message,
        '--',
        ...selectedPaths,
      ], timeout: const Duration(minutes: 2));
      return (await _git(temporary.path, <String>[
        'rev-parse',
        'HEAD^{commit}',
      ])).trim();
    } finally {
      if (worktreeRegistered) {
        try {
          await _git(repositoryRoot, <String>[
            'worktree',
            'remove',
            '--force',
            temporary.path,
          ], timeout: const Duration(minutes: 1));
        } on Object {
          // The original failure is more actionable; stale metadata is pruned below.
          try {
            await _git(repositoryRoot, <String>['worktree', 'prune']);
          } on Object {
            // Best-effort cleanup only.
          }
        }
      }
      if (temporary.existsSync()) {
        temporary.deleteSync(recursive: true);
      }
    }
  }

  static String _safeRelativeBackupPath(String value) {
    final String path = value.trim().replaceAll('\\', '/');
    if (path.isEmpty ||
        path.startsWith('/') ||
        RegExp(r'^[A-Za-z]:').hasMatch(path) ||
        path.split('/').contains('..')) {
      throw const FormatException('备份文件路径必须位于仓库内');
    }
    return path;
  }

  static bool _sameStrings(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (int index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }

  static bool _isSecretFileName(String name, String path) {
    if (name == '.env' ||
        (name.startsWith('.env.') && !name.endsWith('.example'))) {
      return true;
    }
    if (const <String>{
      'id_rsa',
      'id_dsa',
      'id_ecdsa',
      'id_ed25519',
      'credentials',
      'credentials.json',
      '.netrc',
      '_netrc',
    }.contains(name)) {
      return true;
    }
    if (RegExp(r'(^|/)(secrets?|credentials?)(\.|/|$)').hasMatch(path)) {
      return true;
    }
    return name.endsWith('.p12') ||
        name.endsWith('.pfx') ||
        name.endsWith('.key');
  }

  static bool _containsSecret(String content) {
    final String sample = content.length > 1024 * 1024
        ? content.substring(0, 1024 * 1024)
        : content;
    return RegExp(r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----')
            .hasMatch(sample) ||
        RegExp(
          r'(?:github|ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9_]{20,}',
          caseSensitive: false,
        ).hasMatch(sample) ||
        RegExp(
          r'''(?:api[_-]?key|access[_-]?token|client[_-]?secret|password)\s*[:=]\s*['"]?[^\s'"]{12,}''',
          caseSensitive: false,
        ).hasMatch(sample);
  }

  static bool _looksBinaryExtension(String name) => const <String>{
    '.png',
    '.jpg',
    '.jpeg',
    '.gif',
    '.webp',
    '.zip',
    '.7z',
    '.rar',
    '.pdf',
    '.exe',
    '.dll',
    '.so',
    '.dylib',
    '.bin',
    '.db',
    '.sqlite',
    '.onnx',
  }.any(name.endsWith);

  static String _requiredRemoteId(String value) {
    final String remote = value.trim();
    if (!RegExp(r'^[A-Za-z0-9._-]{1,64}$').hasMatch(remote) ||
        remote.startsWith('-')) {
      throw const FormatException('remote 必须是仓库中已有的安全名称');
    }
    return remote;
  }

  static String _requiredBackupBranch(String value) {
    final String branch = value.trim();
    if (!branch.startsWith('backup/') ||
        branch.contains('..') ||
        branch.startsWith('-')) {
      throw const FormatException('目标必须是 preview 生成的 backup/ 分支');
    }
    return branch;
  }

  static String _safeBranchPart(String value) {
    final String safe = value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9._-]+'), '-')
        .replaceAll(RegExp(r'^[-.]+|[-.]+$'), '');
    return safe.isEmpty
        ? 'device'
        : safe.substring(0, safe.length.clamp(0, 48));
  }

  static String _randomPlanId() {
    final Random random = Random.secure();
    return base64UrlEncode(List<int>.generate(24, (_) => random.nextInt(256)))
        .replaceAll('=', '');
  }

  static String _redactRemoteUrl(String value) {
    final Uri? uri = Uri.tryParse(value);
    if (uri != null && uri.hasAuthority && uri.userInfo.isNotEmpty) {
      return uri.replace(userInfo: '***').toString();
    }
    return value.replaceAll(RegExp(r'//[^/@\s]+@'), '//***@');
  }

  static String _safeGitError(Object error) => '$error'
      .replaceFirst('FormatException: ', '')
      .replaceAll(RegExp(r'https?://[^/@\s]+@'), 'https://***@');

  static String _formatBytes(int bytes) => bytes >= 1024 * 1024 * 1024
      ? '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GiB'
      : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';

  static Future<String> _repositoryRoot(String directory) async {
    final String path = directory.trim();
    if (FileSystemEntity.typeSync(path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw const FormatException('请选择存在的项目目录');
    }
    return (await _git(path, <String>['rev-parse', '--show-toplevel'])).trim();
  }

  static String _requiredRef(String value, String label) {
    final String result = value.trim();
    if (result.isEmpty) throw FormatException('请输入$label');
    if (result.startsWith('-')) throw FormatException('$label不能以 - 开头');
    return result;
  }

  static String _requiredRemoteUrl(String value) {
    final String result = value.trim();
    if (result.isEmpty) throw const FormatException('请输入 Git 远端地址');
    if (result.startsWith('-') ||
        result.contains('\n') ||
        result.contains('\r')) {
      throw const FormatException('Git 远端地址格式无效');
    }
    final Uri? uri = Uri.tryParse(result);
    if (uri != null && uri.hasAuthority) {
      if (!const <String>{'ssh', 'http', 'https'}.contains(uri.scheme)) {
        throw const FormatException('只支持 SSH、HTTP 或 HTTPS Git 远端');
      }
      if (uri.userInfo.contains(':')) {
        throw const FormatException('远端地址不得包含明文密码');
      }
    } else if (!RegExp(r'^[^\s@:]+@[^\s:]+:.+$').hasMatch(result)) {
      throw const FormatException('Git 远端地址必须是 SSH、HTTP 或 HTTPS URL');
    }
    return result;
  }

  static String _requiredRemotePath(String value) {
    final String result = value.trim().replaceAll('\\', '/');
    if (result.isEmpty ||
        result.startsWith('/') ||
        result.startsWith('-') ||
        result.split('/').contains('..')) {
      throw const FormatException('远端文件必须是仓库内安全相对路径');
    }
    return result;
  }

  static GitRemoteReference _parseRemoteReference(String line) {
    final List<String> fields = line.trim().split(RegExp(r'\s+'));
    if (fields.length != 2 ||
        !RegExp(r'^[0-9a-fA-F]{40,64}$').hasMatch(fields[0]) ||
        fields[1].isEmpty) {
      throw const FormatException('Git 远端引用输出格式无效');
    }
    return GitRemoteReference(sha: fields[0], ref: fields[1]);
  }

  static Future<String> _git(
    String directory,
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 10),
    int maxOutputBytes = _maxOutputBytes,
  }) async {
    final Process process;
    final String executable = _resolveGitExecutable();
    final bool networkCommand = arguments.any(
      const <String>{'ls-remote', 'fetch', 'clone', 'push'}.contains,
    );
    final String runtimeRoot = File(executable).parent.parent.path;
    try {
      process = await Process.start(
        executable,
        <String>[
          '--no-pager',
          if (Platform.isWindows && networkCommand) ...<String>[
            '--exec-path=$runtimeRoot${Platform.pathSeparator}mingw64'
                '${Platform.pathSeparator}bin',
            '-c',
            'http.sslBackend=openssl',
          ],
          '-C',
          directory,
          ...arguments,
        ],
        runInShell: false,
        environment: const <String, String>{
          'GIT_TERMINAL_PROMPT': '0',
          'GCM_INTERACTIVE': 'Never',
        },
        includeParentEnvironment: true,
      );
    } on ProcessException catch (error) {
      throw StateError('内置 Git 无法启动：${error.message}');
    }
    final Future<List<int>> stdout = _boundedBytes(
      process.stdout,
      process,
      maxBytes: maxOutputBytes,
    );
    final Future<List<int>> stderr = _boundedBytes(
      process.stderr,
      process,
      maxBytes: maxOutputBytes,
    );
    final int exitCode;
    try {
      exitCode = await process.exitCode.timeout(timeout);
    } on TimeoutException {
      process.kill();
      throw FormatException('Git 命令超过 ${timeout.inSeconds} 秒，已停止');
    }
    final String output = utf8.decode(await stdout, allowMalformed: true);
    final String error = utf8.decode(await stderr, allowMalformed: true).trim();
    if (exitCode != 0) {
      throw FormatException(error.isEmpty ? 'Git 命令失败（exit $exitCode）' : error);
    }
    return output;
  }

  static String _resolveGitExecutable() {
    final String separator = Platform.pathSeparator;
    final String executableDirectory = File(Platform.resolvedExecutable)
        .parent
        .path;
    final List<String> candidates = Platform.isWindows
        ? <String>[
            '$executableDirectory${separator}tools${separator}git'
                '${separator}cmd${separator}git.exe',
            '${Directory.current.path}${separator}native${separator}git'
                '${separator}windows${separator}runtime${separator}cmd'
                '${separator}git.exe',
          ]
        : <String>[
            '$executableDirectory$separator..${separator}Resources'
                '${separator}tools${separator}git${separator}bin'
                '${separator}git',
            '${Directory.current.path}${separator}native${separator}git'
                '${separator}macos${separator}runtime${separator}bin'
                '${separator}git',
          ];
    for (final String candidate in candidates) {
      if (File(candidate).existsSync()) return File(candidate).absolute.path;
    }
    throw StateError(
      '安装包缺少内置 Git 运行时，请重新安装 Vibekits。已检查：'
      '${candidates.join('；')}',
    );
  }

  static Future<List<int>> _boundedBytes(
    Stream<List<int>> source,
    Process process, {
    int maxBytes = _maxOutputBytes,
  }) async {
    final BytesBuilder builder = BytesBuilder(copy: false);
    int length = 0;
    await for (final List<int> chunk in source) {
      length += chunk.length;
      if (length > maxBytes) {
        process.kill();
        throw FormatException('Git 输出超过 ${_formatBytes(maxBytes)}，已停止');
      }
      builder.add(chunk);
    }
    return builder.takeBytes();
  }
}

class _GitStatusPath {
  const _GitStatusPath({
    required this.path,
    required this.staged,
    required this.unstaged,
    required this.untracked,
  });

  final String path;
  final bool staged;
  final bool unstaged;
  final bool untracked;
}

List<_GitStatusPath> _parsePorcelain(String value) {
  final List<String> records = value.split('\u0000');
  final List<_GitStatusPath> result = <_GitStatusPath>[];
  for (int index = 0; index < records.length; index++) {
    final String record = records[index];
    if (record.length < 4) continue;
    final String x = record[0];
    final String y = record[1];
    final String path = record.substring(3);
    String? pairedPath;
    if ((x == 'R' || x == 'C') && index + 1 < records.length) {
      pairedPath = records[++index];
    }
    for (final String candidate in <String>[path, ?pairedPath]) {
      if (candidate.isEmpty ||
          candidate.startsWith('/') ||
          candidate.startsWith('\\') ||
          candidate.split(RegExp(r'[\\/]')).contains('..')) {
        continue;
      }
      result.add(
        _GitStatusPath(
          path: candidate.replaceAll('\\', '/'),
          staged: x != ' ' && x != '?',
          unstaged: y != ' ',
          untracked: x == '?' && y == '?',
        ),
      );
    }
  }
  return result;
}
