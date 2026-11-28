import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:surplus_share/core/permission/permission.dart';
import 'package:surplus_share/core/permission/permission_policy.dart';
import 'package:surplus_share/core/permission/permission_provider.dart';

class PermissionGate extends ConsumerWidget {
  const new({
    required this.requiredPermission,
    required this.child,
    this.fallback = const SizedBox.shrink(),
    this.requiredAll = true,
    super.key,
  });

  final Set<Permission> requiredPermission;
  final Widget child;
  final Widget fallback;
  final bool requiredAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allowed = ref.watch(
      currentPermissionProvider.select(
        (perms) => requiredAll
            ? PermissionPolicy.hasAll(perms, requiredPermission)
            : PermissionPolicy.hasAny(perms, requiredPermission),
      ),
    );

    return allowed ? child : fallback;
  }
}
