import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:surplus_share/core/auth/provider/auth_provider.dart';
import 'package:surplus_share/core/permission/permission.dart';
import 'package:surplus_share/core/permission/permission_policy.dart';

final currentPermissionProvider = Provider<Set<Permission>>((ref) {
  final claims = ref.watch(currentClaimsProvider);
  if (claims == null) {
    return const <Permission>{};
  }

  return PermissionPolicy.resolve(
    role: claims.role,
    kycStatus: claims.kycStatus,
    granted: claims.grantedPermissions,
    revoked: claims.revokedPermissions,
  );
});

final ProviderFamily<bool, Permission> hasPermissionProvider = Provider
    .autoDispose
    .family<bool, Permission>((ref, permission) {
      return ref.watch(
        currentPermissionProvider.select((perms) => perms.contains(permission)),
      );
    });

final ProviderFamily<bool, Set<Permission>> hasAllPermissionProvider = Provider
    .autoDispose
    .family<bool, Set<Permission>>((ref, requiredPermission) {
      return ref.watch(
        currentPermissionProvider.select(
          (perms) => PermissionPolicy.hasAll(perms, requiredPermission),
        ),
      );
    });

final ProviderFamily<bool, Set<Permission>> hasAnyPermissionProvider = Provider
    .autoDispose
    .family<bool, Set<Permission>>((ref, candidates) {
      return ref.watch(
        currentPermissionProvider.select(
          (perms) => PermissionPolicy.hasAny(perms, candidates),
        ),
      );
    });
