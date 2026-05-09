import UIKit

final class DeviceCell: UITableViewCell {
    static let reuseIdentifier = "DeviceCell"

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .subtitle, reuseIdentifier: reuseIdentifier)
        accessoryType = .disclosureIndicator
        detailTextLabel?.numberOfLines = 2
        textLabel?.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        detailTextLabel?.font = UIFont.systemFont(ofSize: 12, weight: .regular)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

