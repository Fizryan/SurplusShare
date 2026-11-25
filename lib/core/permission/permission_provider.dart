// import 'package:flutter_riverpod/flutter_riverpod.dart';
// import 'package:flutter_riverpod/misc.dart';
// import 'package:surplus_share/core/permission/permission.dart';

// final currentPermissionProvider = Provider<Set<Permission>>((ref) {});

// final ProviderFamily<bool, Permission> hasPermissionProvider =
//     Provider.family<bool, Permission>((ref, permission) {
//       return ref.watch(
//         currentPermissionProvider.select((perms) =>
//           perms.contains(permission)),
//       );
//     });

// final ProviderFamily<bool, Set<Permission>> hasAllPermissionProvider =
//     Provider.family<bool, Set<Permission>>((ref, requiredPermission) {
//       return ref.watch(
//         currentPermissionProvider.select(
//           (perms) => perms.containsAll(requiredPermission),
//         ),
//       );
//     });
