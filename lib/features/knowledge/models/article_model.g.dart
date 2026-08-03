// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'article_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ArticleModelAdapter extends TypeAdapter<ArticleModel> {
  @override
  final int typeId = 17;

  @override
  ArticleModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ArticleModel(
      id: fields[0] as String,
      title: fields[1] as String,
      body: fields[2] as String,
      section: fields[3] as ArticleSection,
      tags: (fields[4] as List).cast<String>(),
      createdAt: fields[5] as DateTime,
      updatedAt: fields[6] as DateTime,
      builtIn: fields[7] as bool,
      pinned: fields[8] as bool,
      parentId: fields[9] as String?,
      isFolder: fields[10] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, ArticleModel obj) {
    writer
      ..writeByte(11)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.body)
      ..writeByte(3)
      ..write(obj.section)
      ..writeByte(4)
      ..write(obj.tags)
      ..writeByte(5)
      ..write(obj.createdAt)
      ..writeByte(6)
      ..write(obj.updatedAt)
      ..writeByte(7)
      ..write(obj.builtIn)
      ..writeByte(8)
      ..write(obj.pinned)
      ..writeByte(9)
      ..write(obj.parentId)
      ..writeByte(10)
      ..write(obj.isFolder);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ArticleModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class ArticleSectionAdapter extends TypeAdapter<ArticleSection> {
  @override
  final int typeId = 16;

  @override
  ArticleSection read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return ArticleSection.about;
      case 1:
        return ArticleSection.playbook;
      case 2:
        return ArticleSection.guide;
      case 3:
        return ArticleSection.finance;
      case 4:
        return ArticleSection.personal;
      default:
        return ArticleSection.about;
    }
  }

  @override
  void write(BinaryWriter writer, ArticleSection obj) {
    switch (obj) {
      case ArticleSection.about:
        writer.writeByte(0);
        break;
      case ArticleSection.playbook:
        writer.writeByte(1);
        break;
      case ArticleSection.guide:
        writer.writeByte(2);
        break;
      case ArticleSection.finance:
        writer.writeByte(3);
        break;
      case ArticleSection.personal:
        writer.writeByte(4);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ArticleSectionAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
