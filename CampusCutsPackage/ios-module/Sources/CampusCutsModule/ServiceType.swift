//
//  ServiceType.swift
//  CampusCutsModule
//
//  Granular provider kinds for browse filters and cards (Barber, Makeup, Nails, …).
//

import Foundation

/// Kind of service provider for toolbar tags and list filtering (`all` shows everyone).
public enum ServiceType: String, CaseIterable, Identifiable, Sendable, Hashable {
    case all
    case barber
    case makeup
    case tanning
    case nails
    case lashes
    case braids
    case hair
    case massage
    case fitness

    public var id: String { rawValue }

    public var toolbarTitle: String {
        switch self {
        case .all: return "All"
        case .barber: return "Barber"
        case .makeup: return "Makeup"
        case .tanning: return "Tanning"
        case .nails: return "Nails"
        case .lashes: return "Lashes"
        case .braids: return "Braids"
        case .hair: return "Hair"
        case .massage: return "Massage"
        case .fitness: return "Fitness"
        }
    }

    public var systemImageName: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .barber: return "scissors"
        case .makeup: return "paintpalette.fill"
        case .tanning: return "sun.max.fill"
        case .nails: return "hand.raised.fill"
        case .lashes: return "eye"
        case .braids: return "line.3.horizontal"
        case .hair: return "comb.fill"
        case .massage: return "leaf.fill"
        case .fitness: return "figure.run"
        }
    }

    /// Next value when cycling (e.g. programmatic tools); UI browse uses the tag strip instead.
    public var next: ServiceType {
        let order = Self.allCases
        guard let i = order.firstIndex(of: self) else { return .all }
        return order[(i + 1) % order.count]
    }
}
