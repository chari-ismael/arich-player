// lib/models/category.dart

/// Modèle de catégorie utilisé par Xtream API ET M3uParser.
/// ⚠️ Le nom de classe est [Category] (et non StreamCategory) pour rester
/// cohérent avec les imports dans m3u_parser.dart et iptv_provider.dart.
class Category {
  final String categoryId;
  final String categoryName;
  final int parentId;

  const Category({
    required this.categoryId,
    required this.categoryName,
    this.parentId = 0,
  });

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      categoryId:   json['category_id']?.toString() ?? '0',
      categoryName: json['category_name']?.toString() ?? 'Inconnu',
      parentId:     int.tryParse(json['parent_id']?.toString() ?? '0') ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
    'id':   categoryId,
    'name': categoryName,
  };
}