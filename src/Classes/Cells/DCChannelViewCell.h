//
//  DCChannelViewCell.h
//  Discord Classic
//
//  Created by XML on 23/12/24.
//  Copyright (c) 2024 Julian Triveri. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface DCChannelViewCell : UITableViewCell

@property (weak, nonatomic) IBOutlet UIImageView *activityIndicatorLed;
@property (weak, nonatomic) IBOutlet UIImageView *messageIndicator;
@property (weak, nonatomic) IBOutlet UILabel *type;
@property (weak, nonatomic) IBOutlet UILabel *channelName;

@end
