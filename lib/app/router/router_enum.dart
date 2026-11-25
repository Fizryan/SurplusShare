import 'package:surplus_share/core/permission/permission.dart';

enum GroupCategory {
  auth(name: 'Auth'),
  shell(name: 'Shell');

  new({required this.name});

  final String name;
}

enum RouteEnum {
  login(
    path: '/login',
    name: 'Login',
    group: GroupCategory.auth,
    requiredAuth: false,
  ),
  register(
    path: '/register',
    name: 'Register',
    group: GroupCategory.auth,
    requiredAuth: false,
  ),
  unauthorized(
    path: '/unauthorized',
    name: 'Akses Dilarang',
    group: GroupCategory.auth,
  ),

  feed(
    path: '/feed',
    name: 'Beranda',
    group: GroupCategory.shell,
    requiredPermission: {Permission.browseDiscountListings},
  );

  new({
    required this.path,
    required this.name,
    required this.group,
    this.requiredAuth = true,
    this.requiredPermission = const <Permission>{},
  });

  final String path;
  final String name;
  final GroupCategory? group;
  final bool requiredAuth;
  final Set<Permission> requiredPermission;
}
