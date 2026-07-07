//
//  SharedObject.swift
//
//
//  Created by Lorenzo Fiamingo on 31/07/2020.
//

import Foundation
import SwiftUI
import Combine

/// A property wrapper type for an observable object supplied with an id or created at the moment.
@available(watchOS 6.0, tvOS 13.0, iOS 13.0, OSX 10.15, *)
@MainActor
@propertyWrapper
public struct SharedObject<ObjectType, ID>: DynamicProperty where ObjectType: ObservableObject, ID: Hashable {
	
	@ObservedObject private var container: Object<ObjectType>
	
	public var wrappedValue: ObjectType {
		get {
            container.object
        }
		nonmutating set {
            container.object = newValue
        }
	}
	
	public var projectedValue: SharedObject.Wrapper {
		.init(container.object)
	}
	
//	init(wrappedValue: ObjectType, _ id: ID) {
//        container = .init(wrappedValue: wrappedValue, id: id)
//	}
    
    public func silence() {
        container.pausable?.state = .stopped
    }
    
    public func awake() {
        container.pausable?.state = .normal
    }
    
	@MainActor
	public init(_ id: ID) where ObjectType: SharableObject {
        if let object = SharedRepository.getObject(for: id.hashValue) as? ObjectType {
            container = .init(wrappedValue: object, id: id)
        } else {
            container = .init(wrappedValue: SharedRepository.insert(ObjectType.initialValue, for: id.hashValue), id: id)
        }
	}
	
	private final class Object<Wrapped: ObservableObject>: ObservableObject {

		var object: Wrapped

        /*
         This container is created wherever a @Relay is called.
         But, there's always only 1 relay instance.

         We simply subscribe to each, propogate view updates.
         While maintaining data consistency in 1 singular location.
         */

        weak var pausable: PausableSinkSubscriber<Wrapped.ObjectWillChangePublisher.Output, Never>? = nil

        deinit {
            pausable?.cancel()
            pausable = nil
            Prospector.shared.node(for: self.id)?.remove(includeChildren: true)
            //GraniteLog("Shareable deinit", level: .debug)
        }

        let id: UUID = .init()

		init(wrappedValue: Wrapped, id: ID) where Wrapped: SharableObject {
            self.object = wrappedValue
            
            let currentNodeId = Prospector.shared.currentNode?.id
            Prospector.shared.currentNode?.addChild(id: self.id,
                                                    label: String(reflecting: Self.self),
                                                    type: .relayNetwork)
            Prospector.shared.push(id: self.id, .relayNetwork)
            
            // DispatchQueue.main (not RunLoop.main): RunLoop.main only fires in the
            // default run-loop mode, so shared-object → UI delivery stalls while a finger
            // is down (touch tracking runs in UITrackingRunLoopMode). This mirrors the fix
            // already applied to GraniteCommand's component observer.
            pausable = wrappedValue
                .objectWillChange
                .debounce(for: .seconds(0.2), scheduler: DispatchQueue.main)
                .pausableSink { [weak self] _ in
                self?.objectWillChange.send()
            }
            pausable?.state = .normal
            
            if let currentNodeId,
               let pausable  {
                let nodeLabel = Prospector.shared.node(for: currentNodeId)?.label ?? ""
                //GraniteLog("Shared sub'd under id: \(currentNodeId) | \(nodeLabel)", level: .debug)
                Prospector.shared.currentNode?.addProspect(pausable, for: self.id)
            } else if currentNodeId == nil {
                //GraniteLog("No current node exists: \(String(reflecting: ObjectType.self))", level: .debug)
            }
            
            Prospector.shared.pop(.relayNetwork)
		}
	}
	
	@dynamicMemberLookup
	public struct Wrapper {
		private let object: ObjectType
		
		init(_ object: ObjectType) {
			self.object = object
		}
		
		public subscript<Subject>(dynamicMember keyPath: ReferenceWritableKeyPath<ObjectType, Subject>) -> Binding<Subject> {
			.init {
				object[keyPath: keyPath]
			} set: { newValue in
				object[keyPath: keyPath] = newValue
			}
		}
	}
}
/// Process-wide registry backing every `@SharedObject` / `@Relay`.
///
/// Shared services (relays) are intentionally retained for the lifetime of the app: a
/// `.online` relay is a singleton whose state must survive individual view teardown, so
/// entries are **not** evicted automatically (auto-eviction on the last container's
/// `deinit` would risk dropping and re-defaulting live service state during transient
/// SwiftUI view churn). Callers that own a genuinely scoped service can release it
/// explicitly via ``remove(for:)``.
///
/// Access is guarded by an internal lock (`@unchecked Sendable`) because the stored
/// values are heterogeneous `Any` and are touched from both the main thread and reducer
/// queues during service construction.
final class SharedRepository: @unchecked Sendable {

    static let shared = SharedRepository()

    private let lock = NSLock()
    private var objects: [Int: Any] = [:]

    static func getObject(for key: Int) -> Any? {
        shared.lock.lock()
        defer { shared.lock.unlock() }
        return shared.objects[key]
    }

    @discardableResult
    static func insert<ObjectType>(_ object: ObjectType, for key: Int) -> ObjectType {
        shared.lock.lock()
        defer { shared.lock.unlock() }
        shared.objects[key] = object
        return object
    }

    /// Explicitly releases a shared object. Only safe when the caller knows no other
    /// view still references the service (e.g. a scoped, single-owner relay).
    static func remove(for key: Int) {
        shared.lock.lock()
        defer { shared.lock.unlock() }
        shared.objects[key] = nil
    }
}
