//
//  TOCItem.swift
//  md-glanceCore
//
//  目录项数据模型
//

import Foundation

/// 目录项
public struct TOCItem: Identifiable, Equatable {
    public let id: String
    public let level: Int
    public let title: String
    public let slug: String

    public init(level: Int, title: String, slug: String) {
        self.id = slug
        self.level = level
        self.title = title
        self.slug = slug
    }
}
