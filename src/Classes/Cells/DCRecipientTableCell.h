//
//  DCRecipientTableCell.h
//  Discord Classic
//
//  Created by XML on 22/12/24.
//  Copyright (c) 2024 bag.xml. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface DCRecipientTableCell : UITableViewCell
@property (weak, nonatomic) IBOutlet UIImageView *userPFP;
@property (weak, nonatomic) IBOutlet UIImageView *statusLight;
@property (weak, nonatomic) IBOutlet UILabel *userName;

@end
