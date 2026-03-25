import CloudKit

enum CloudKitConfig {
    static let containerID = "iCloud.com.hotel.frontdesk"
    static let container = CKContainer(identifier: containerID)
    static let database = container.privateCloudDatabase
}
