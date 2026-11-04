import Foundation

public struct FlexibleString: Codable, Equatable, Hashable {
  public let value: String

  public init(_ value: String) {
    self.value = value
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let str = try? container.decode(String.self) {
      self.value = str
    } else if let intVal = try? container.decode(Int.self) {
      self.value = String(intVal)
    } else if let doubleVal = try? container.decode(Double.self) {
      self.value = String(Int(doubleVal))
    } else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Expected String or number for FlexibleString"
      )
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(value)
  }
}

public struct FlexibleInt: Codable, Equatable, Hashable {
  public let value: Int

  public init(_ value: Int) {
    self.value = value
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let intVal = try? container.decode(Int.self) {
      self.value = intVal
    } else if let str = try? container.decode(String.self) {
      if let parsed = Int(str) {
        self.value = parsed
      } else if let dbl = Double(str) {
        self.value = Int(dbl)
      } else {
        throw DecodingError.dataCorruptedError(
          in: container,
          debugDescription: "Cannot parse Int from string: \(str)"
        )
      }
    } else if let dbl = try? container.decode(Double.self) {
      self.value = Int(dbl)
    } else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Expected Int or numeric string for FlexibleInt"
      )
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(value)
  }
}

extension KeyedDecodingContainer {
  public func decodeFlexibleString(forKey key: Key) throws -> String {
    try decode(FlexibleString.self, forKey: key).value
  }

  public func decodeFlexibleStringIfPresent(forKey key: Key) throws -> String? {
    try decodeIfPresent(FlexibleString.self, forKey: key)?.value
  }

  public func decodeFlexibleInt(forKey key: Key) throws -> Int {
    try decode(FlexibleInt.self, forKey: key).value
  }

  public func decodeFlexibleIntIfPresent(forKey key: Key) throws -> Int? {
    try decodeIfPresent(FlexibleInt.self, forKey: key)?.value
  }
}

extension JSONDecoder {
  public static var quick: JSONDecoder {
    let decoder = JSONDecoder()
    let withFractional = ISO8601DateFormatter()
    withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let standard = ISO8601DateFormatter()
    standard.formatOptions = [.withInternetDateTime]

    let fallbackDateFormatter: DateFormatter = {
      let df = DateFormatter()
      df.locale = Locale(identifier: "en_US_POSIX")
      df.timeZone = TimeZone(secondsFromGMT: 0)
      df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZZZZZ"
      return df
    }()

    decoder.dateDecodingStrategy = .custom { decoder in
      let container = try decoder.singleValueContainer()
      let dateStr = try container.decode(String.self)
      if let date = withFractional.date(from: dateStr) ?? standard.date(from: dateStr) ?? fallbackDateFormatter.date(from: dateStr) {
        return date
      }
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Invalid ISO 8601 date string: \(dateStr)"
      )
    }
    return decoder
  }
}

extension JSONEncoder {
  public static var quick: JSONEncoder {
    let encoder = JSONEncoder()
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    encoder.dateEncodingStrategy = .custom { date, encoder in
      var container = encoder.singleValueContainer()
      try container.encode(formatter.string(from: date))
    }
    return encoder
  }
}

public struct QuickSnapshot: Codable, Equatable {
  public struct Family: Codable, Equatable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
      self.id = id
      self.name = name
    }

    enum CodingKeys: String, CodingKey {
      case id, name
    }

    public init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      id = try container.decodeFlexibleString(forKey: .id)
      name = try container.decode(String.self, forKey: .name)
    }
  }

  public struct Task: Codable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let type: String
    public let durationMinutes: Int
    public let coinValue: Int

    public init(id: String, title: String, type: String, durationMinutes: Int, coinValue: Int) {
      self.id = id
      self.title = title
      self.type = type
      self.durationMinutes = durationMinutes
      self.coinValue = coinValue
    }

    enum CodingKeys: String, CodingKey {
      case id, title, type, durationMinutes, coinValue
    }

    public init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      id = try container.decodeFlexibleString(forKey: .id)
      title = try container.decode(String.self, forKey: .title)
      type = try container.decode(String.self, forKey: .type)
      durationMinutes = try container.decodeFlexibleInt(forKey: .durationMinutes)
      coinValue = try container.decodeFlexibleInt(forKey: .coinValue)
    }
  }

  public struct Upcoming: Codable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let type: String
    public let startsAt: Date
    public let endsAt: Date?
    public let status: String

    public init(id: String, title: String, type: String, startsAt: Date, endsAt: Date?, status: String) {
      self.id = id
      self.title = title
      self.type = type
      self.startsAt = startsAt
      self.endsAt = endsAt
      self.status = status
    }

    enum CodingKeys: String, CodingKey {
      case id, title, type, startsAt, endsAt, status
    }

    public init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      id = try container.decodeFlexibleString(forKey: .id)
      title = try container.decode(String.self, forKey: .title)
      type = try container.decode(String.self, forKey: .type)
      startsAt = try container.decode(Date.self, forKey: .startsAt)
      endsAt = try container.decodeIfPresent(Date.self, forKey: .endsAt)
      status = try container.decode(String.self, forKey: .status)
    }
  }

  public struct Running: Codable, Equatable {
    public let id: String
    public let title: String
    public let type: String
    public let startedAt: Date
    public let clientRef: String?

    public init(id: String, title: String, type: String, startedAt: Date, clientRef: String?) {
      self.id = id
      self.title = title
      self.type = type
      self.startedAt = startedAt
      self.clientRef = clientRef
    }

    enum CodingKeys: String, CodingKey {
      case id, title, type, startedAt, clientRef
    }

    public init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      id = try container.decodeFlexibleString(forKey: .id)
      title = try container.decode(String.self, forKey: .title)
      type = try container.decode(String.self, forKey: .type)
      startedAt = try container.decode(Date.self, forKey: .startedAt)
      clientRef = try container.decodeIfPresent(String.self, forKey: .clientRef)
    }
  }

  public let family: Family
  public let balance: Int
  public let needsYou: Int
  public let tasks: [Task]
  public let upcoming: [Upcoming]
  public let running: Running?
  public let serverTime: Date

  public init(
    family: Family,
    balance: Int,
    needsYou: Int,
    tasks: [Task],
    upcoming: [Upcoming],
    running: Running?,
    serverTime: Date
  ) {
    self.family = family
    self.balance = balance
    self.needsYou = needsYou
    self.tasks = tasks
    self.upcoming = upcoming
    self.running = running
    self.serverTime = serverTime
  }

  enum CodingKeys: String, CodingKey {
    case family, balance, needsYou, tasks, upcoming, running, serverTime
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    family = try container.decode(Family.self, forKey: .family)
    balance = try container.decodeFlexibleInt(forKey: .balance)
    needsYou = try container.decodeFlexibleInt(forKey: .needsYou)
    tasks = try container.decode([Task].self, forKey: .tasks)
    upcoming = try container.decode([Upcoming].self, forKey: .upcoming)
    running = try container.decodeIfPresent(Running.self, forKey: .running)
    serverTime = try container.decode(Date.self, forKey: .serverTime)
  }

  public func startedTask(now: Date = Date()) -> Upcoming? {
    upcoming.first { item in
      guard item.status == "approved" else { return false }
      guard item.startsAt <= now else { return false }
      guard let endsAt = item.endsAt else { return false }
      return now < endsAt
    }
  }

  public func awaitingConfirmation(now: Date = Date()) -> Upcoming? {
    let twoHoursAgo = now.addingTimeInterval(-2 * 3600)
    return upcoming.first { item in
      guard item.status == "approved" else { return false }
      guard let endsAt = item.endsAt else { return false }
      return endsAt <= now && item.startsAt >= twoHoursAgo
    }
  }

  public func nextUpcoming(now: Date = Date()) -> Upcoming? {
    upcoming.first { item in
      item.startsAt > now
    }
  }
}

public struct QuickActivity: Codable, Equatable, Identifiable {
  public let id: String
  public let title: String?
  public let type: String?
  public let status: String?
  public let startsAt: Date?
  public let endsAt: Date?
  public let runningSince: Date?
  public let clientRef: String?
  public let durationMinutes: Int?
  public let coinValue: Int?

  public init(
    id: String,
    title: String? = nil,
    type: String? = nil,
    status: String? = nil,
    startsAt: Date? = nil,
    endsAt: Date? = nil,
    runningSince: Date? = nil,
    clientRef: String? = nil,
    durationMinutes: Int? = nil,
    coinValue: Int? = nil
  ) {
    self.id = id
    self.title = title
    self.type = type
    self.status = status
    self.startsAt = startsAt
    self.endsAt = endsAt
    self.runningSince = runningSince
    self.clientRef = clientRef
    self.durationMinutes = durationMinutes
    self.coinValue = coinValue
  }

  enum CodingKeys: String, CodingKey {
    case id
    case title
    case type
    case status
    case startsAt = "starts_at"
    case endsAt = "ends_at"
    case runningSince = "running_since"
    case clientRef = "client_ref"
    case durationMinutes = "duration_minutes"
    case coinValue = "coin_value"
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decodeFlexibleString(forKey: .id)
    title = try container.decodeIfPresent(String.self, forKey: .title)
    type = try container.decodeIfPresent(String.self, forKey: .type)
    status = try container.decodeIfPresent(String.self, forKey: .status)
    startsAt = try container.decodeIfPresent(Date.self, forKey: .startsAt)
    endsAt = try container.decodeIfPresent(Date.self, forKey: .endsAt)
    runningSince = try container.decodeIfPresent(Date.self, forKey: .runningSince)
    clientRef = try container.decodeIfPresent(String.self, forKey: .clientRef)
    durationMinutes = try container.decodeFlexibleIntIfPresent(forKey: .durationMinutes)
    coinValue = try container.decodeFlexibleIntIfPresent(forKey: .coinValue)
  }
}

public struct QuickActionResult: Codable, Equatable {
  public let activity: QuickActivity?
  public let replayed: Bool
  public let warning: String?
  public let undone: Bool
  public let completed: Bool?
  public let coinsAwarded: Int?
  public let cancelled: Bool

  public init(
    activity: QuickActivity? = nil,
    replayed: Bool = false,
    warning: String? = nil,
    undone: Bool = false,
    completed: Bool? = nil,
    coinsAwarded: Int? = nil,
    cancelled: Bool = false
  ) {
    self.activity = activity
    self.replayed = replayed
    self.warning = warning
    self.undone = undone
    self.completed = completed
    self.coinsAwarded = coinsAwarded
    self.cancelled = cancelled
  }

  enum CodingKeys: String, CodingKey {
    case activity
    case replayed
    case warning
    case undone
    case completed
    case coinsAwarded
    case cancelled
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.replayed = (try? container.decode(Bool.self, forKey: .replayed)) ?? false
    self.warning = try? container.decodeIfPresent(String.self, forKey: .warning)
    self.undone = (try? container.decode(Bool.self, forKey: .undone)) ?? false
    self.completed = try? container.decodeIfPresent(Bool.self, forKey: .completed)
    self.coinsAwarded = try? container.decodeFlexibleIntIfPresent(forKey: .coinsAwarded)
    self.cancelled = (try? container.decode(Bool.self, forKey: .cancelled)) ?? false

    if container.contains(.activity) {
      self.activity = try? container.decodeIfPresent(QuickActivity.self, forKey: .activity)
    } else {
      self.activity = try? QuickActivity(from: decoder)
    }
  }
}
