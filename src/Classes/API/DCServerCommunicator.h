//
//  DCServerCommunicator.h
//  Discord Classic
//
//  Created by bag.xml on 3/4/18.
//  Copyright (c) 2018 bag.xml. All rights reserved.
//

#import <Foundation/Foundation.h>
#include <objc/NSObjCRuntime.h>
#import "DCChannelListViewController.h"
#import "DCChatViewController.h"
#import "DCGuildListViewController.h"
#import "DCUserInfo.h"
#import "WSWebSocket.h"

// following info courtesy of https://discord.neko.wtf/
typedef NS_ENUM(NSUInteger, DCGatewayOpCode) {
    DCGatewayOpCodeDispatch                           = 0,
    DCGatewayOpCodeHeartbeat                          = 1,
    DCGatewayOpCodeIdentify                           = 2,
    DCGatewayOpCodePresenceUpdate                     = 3,
    DCGatewayOpCodeVoiceStateUpdate                   = 4,
    DCGatewayOpCodeVoiceServerPing                    = 5,
    DCGatewayOpCodeResume                             = 6,
    DCGatewayOpCodeReconnect                          = 7,
    DCGatewayOpCodeRequestGuildMembers                = 8,
    DCGatewayOpCodeInvalidSession                     = 9,
    DCGatewayOpCodeHello                              = 10,
    DCGatewayOpCodeHeartbeatAck                       = 11,
    DCGatewayOpCodeCallConnect                        = 13,
    DCGatewayOpCodeGuildSubscriptions                 = 14,
    DCGatewayOpCodeLobbyConnect                       = 15,
    DCGatewayOpCodeLobbyDisconnect                    = 16,
    DCGatewayOpCodeLobbyVoiceStatesUpdate             = 17,
    DCGatewayOpCodeStreamCreate                       = 18,
    DCGatewayOpCodeStreamDelete                       = 19,
    DCGatewayOpCodeStreamWatch                        = 20,
    DCGatewayOpCodeStreamPing                         = 21,
    DCGatewayOpCodeStreamSetPaused                    = 22,
    DCGatewayOpCodeRequestGuildApplicationCommands    = 24,
    DCGatewayOpCodeEmbeddedActivityLaunch             = 25,
    DCGatewayOpCodeEmbeddedActivityClose              = 26,
    DCGatewayOpCodeEmbeddedActivityUpdate             = 27,
    DCGatewayOpCodeRequestForumUnreads                = 28,
    DCGatewayOpCodeRemoteCommand                      = 29,
    DCGatewayOpCodeGetDeletedEntityIdsNotMatchingHash = 30,
    DCGatewayOpCodeRequestSoundboardSounds            = 31,
    DCGatewayOpCodeSpeedTestCreate                    = 32,
    DCGatewayOpCodeSpeedTestDelete                    = 33,
    DCGatewayOpCodeRequestLastMessages                = 34,
    DCGatewayOpCodeSearchRecentMember                 = 35,
    // these from discord itself
    DCGatewayOpCodeRequestChannelStatuses             = 36,
    DCGatewayOpCodeGuildSubscriptionsBulk             = 37,
    DCGatewayOpCodeGuildChannelsResync                = 38,
    DCGatewayOpCodeRequestChannelMemberCount          = 39,
    DCGatewayOpCodeQosHeartbeat                       = 40,
    DCGatewayOpCodeUpdateTimeSpentSessionId           = 41,
};

typedef NS_ENUM(uint64_t, DCGatewayCapabilities) {
    DCGatewayCapabilitiesLazyUserNotes                      = (uint64_t)1 << 0,
    DCGatewayCapabilitiesNoAffineUserIds                    = (uint64_t)1 << 1,
    DCGatewayCapabilitiesVersionedReadStates                = (uint64_t)1 << 2,
    DCGatewayCapabilitiesVersionedUserGuildSettings         = (uint64_t)1 << 3,
    DCGatewayCapabilitiesDedupeUserObjects                  = (uint64_t)1 << 4,
    DCGatewayCapabilitiesPrioritizedReadyPayload            = (uint64_t)1 << 5,
    DCGatewayCapabilitiesMultipleGuildExperimentPopulations = (uint64_t)1 << 6,
    DCGatewayCapabilitiesNonChannelReadStates               = (uint64_t)1 << 7,
    DCGatewayCapabilitiesAuthTokenRefresh                   = (uint64_t)1 << 8,
    DCGatewayCapabilitiesUserSettingsProto                  = (uint64_t)1 << 9,
    DCGatewayCapabilitiesClientStateV2                      = (uint64_t)1 << 10,
    DCGatewayCapabilitiesPassiveGuildUpdate                 = (uint64_t)1 << 11,
    DCGatewayCapabilitiesAutoCallConnect                    = (uint64_t)1 << 12,
    DCGatewayCapabilitiesDebounceMessageReactions           = (uint64_t)1 << 13,
    DCGatewayCapabilitiesPassiveGuildUpdateV2               = (uint64_t)1 << 14,
    DCGatewayCapabilitiesAutoLobbyConnect                   = (uint64_t)1 << 16
};

#define ACTIVITY_START @"ACTIVITY_START"
#define ACTIVITY_USER_ACTION @"ACTIVITY_USER_ACTION"
#define APPLICATION_COMMAND_AUTOCOMPLETE_RESPONSE @"APPLICATION_COMMAND_AUTOCOMPLETE_RESPONSE"
#define APPLICATION_COMMAND_PERMISSIONS_UPDATE @"APPLICATION_COMMAND_PERMISSIONS_UPDATE"
#define AUTH_SESSION_CHANGE @"AUTH_SESSION_CHANGE"
#define AUTO_MODERATION_MENTION_RAID_DETECTION @"AUTO_MODERATION_MENTION_RAID_DETECTION"
#define BILLING_POPUP_BRIDGE_CALLBACK @"BILLING_POPUP_BRIDGE_CALLBACK"
#define BILLING_REFERRAL_TRIAL_OFFER_UPDATE @"BILLING_REFERRAL_TRIAL_OFFER_UPDATE"
#define BURST_CREDIT_BALANCE_UPDATE @"BURST_CREDIT_BALANCE_UPDATE"
#define CALL_CREATE @"CALL_CREATE"
#define CALL_DELETE @"CALL_DELETE"
#define CALL_UPDATE @"CALL_UPDATE"
#define CHANNEL_CREATE @"CHANNEL_CREATE"
#define CHANNEL_DELETE @"CHANNEL_DELETE"
#define CHANNEL_PINS_ACK @"CHANNEL_PINS_ACK"
#define CHANNEL_PINS_UPDATE @"CHANNEL_PINS_UPDATE"
#define CHANNEL_RECIPIENT_ADD @"CHANNEL_RECIPIENT_ADD"
#define CHANNEL_RECIPIENT_REMOVE @"CHANNEL_RECIPIENT_REMOVE"
#define CHANNEL_UPDATE @"CHANNEL_UPDATE"
#define CONSOLE_COMMAND_UPDATE @"CONSOLE_COMMAND_UPDATE"
#define CREATOR_MONETIZATION_RESTRICTIONS_UPDATE @"CREATOR_MONETIZATION_RESTRICTIONS_UPDATE"
#define DELETED_ENTITY_IDS @"DELETED_ENTITY_IDS"
#define EMBEDDED_ACTIVITY_UPDATE_EVENT @"EMBEDDED_ACTIVITY_UPDATE"
#define ENTITLEMENT_CREATE @"ENTITLEMENT_CREATE"
#define ENTITLEMENT_DELETE @"ENTITLEMENT_DELETE"
#define ENTITLEMENT_UPDATE @"ENTITLEMENT_UPDATE"
#define FORUM_UNREADS @"FORUM_UNREADS"
#define FRIEND_SUGGESTION_CREATE @"FRIEND_SUGGESTION_CREATE"
#define FRIEND_SUGGESTION_DELETE @"FRIEND_SUGGESTION_DELETE"
#define GENERIC_PUSH_NOTIFICATION_SENT @"GENERIC_PUSH_NOTIFICATION_SENT"
#define GIFT_CODE_CREATE @"GIFT_CODE_CREATE"
#define GIFT_CODE_UPDATE @"GIFT_CODE_UPDATE"
#define GUILD_APPLICATION_COMMAND_INDEX_UPDATE @"GUILD_APPLICATION_COMMAND_INDEX_UPDATE"
#define GUILD_BAN_ADD @"GUILD_BAN_ADD"
#define GUILD_BAN_REMOVE @"GUILD_BAN_REMOVE"
#define GUILD_CREATE @"GUILD_CREATE"
#define GUILD_DELETE @"GUILD_DELETE"
#define GUILD_DIRECTORY_ENTRY_CREATE @"GUILD_DIRECTORY_ENTRY_CREATE"
#define GUILD_DIRECTORY_ENTRY_DELETE @"GUILD_DIRECTORY_ENTRY_DELETE"
#define GUILD_DIRECTORY_ENTRY_UPDATE @"GUILD_DIRECTORY_ENTRY_UPDATE"
#define GUILD_EMOJIS_UPDATE @"GUILD_EMOJIS_UPDATE"
#define GUILD_FEATURE_ACK @"GUILD_FEATURE_ACK"
#define GUILD_INTEGRATIONS_UPDATE @"GUILD_INTEGRATIONS_UPDATE"
#define GUILD_JOIN_REQUEST_CREATE @"GUILD_JOIN_REQUEST_CREATE"
#define GUILD_JOIN_REQUEST_DELETE @"GUILD_JOIN_REQUEST_DELETE"
#define GUILD_JOIN_REQUEST_UPDATE @"GUILD_JOIN_REQUEST_UPDATE"
#define GUILD_MEMBER_ADD @"GUILD_MEMBER_ADD"
#define GUILD_MEMBER_LIST_UPDATE @"GUILD_MEMBER_LIST_UPDATE"
#define GUILD_MEMBER_REMOVE @"GUILD_MEMBER_REMOVE"
#define GUILD_MEMBER_UPDATE @"GUILD_MEMBER_UPDATE"
#define GUILD_MEMBERS_CHUNK @"GUILD_MEMBERS_CHUNK"
#define GUILD_ROLE_CREATE @"GUILD_ROLE_CREATE"
#define GUILD_ROLE_DELETE @"GUILD_ROLE_DELETE"
#define GUILD_ROLE_UPDATE @"GUILD_ROLE_UPDATE"
#define GUILD_SCHEDULED_EVENT_CREATE @"GUILD_SCHEDULED_EVENT_CREATE"
#define GUILD_SCHEDULED_EVENT_DELETE @"GUILD_SCHEDULED_EVENT_DELETE"
#define GUILD_SCHEDULED_EVENT_UPDATE @"GUILD_SCHEDULED_EVENT_UPDATE"
#define GUILD_SCHEDULED_EVENT_USER_ADD @"GUILD_SCHEDULED_EVENT_USER_ADD"
#define GUILD_SCHEDULED_EVENT_USER_REMOVE @"GUILD_SCHEDULED_EVENT_USER_REMOVE"
#define GUILD_SOUNDBOARD_SOUND_CREATE @"GUILD_SOUNDBOARD_SOUND_CREATE"
#define GUILD_SOUNDBOARD_SOUND_DELETE @"GUILD_SOUNDBOARD_SOUND_DELETE"
#define GUILD_SOUNDBOARD_SOUND_UPDATE @"GUILD_SOUNDBOARD_SOUND_UPDATE"
#define GUILD_SOUNDBOARD_SOUNDS_UPDATE @"GUILD_SOUNDBOARD_SOUNDS_UPDATE"
#define GUILD_STICKERS_UPDATE @"GUILD_STICKERS_UPDATE"
#define GUILD_UPDATE @"GUILD_UPDATE"
#define INTEGRATION_CREATE @"INTEGRATION_CREATE"
#define INTEGRATION_DELETE @"INTEGRATION_DELETE"
#define INTERACTION_CREATE @"INTERACTION_CREATE"
#define INTERACTION_FAILURE @"INTERACTION_FAILURE"
#define INTERACTION_IFRAME_MODAL_CREATE @"INTERACTION_IFRAME_MODAL_CREATE"
#define INTERACTION_MODAL_CREATE @"INTERACTION_MODAL_CREATE"
#define INTERACTION_SUCCESS @"INTERACTION_SUCCESS"
#define LAST_MESSAGES @"LAST_MESSAGES"
#define LIBRARY_APPLICATION_UPDATE @"LIBRARY_APPLICATION_UPDATE"
#define LOBBY_CREATE @"LOBBY_CREATE"
#define LOBBY_DELETE @"LOBBY_DELETE"
#define LOBBY_MEMBER_CONNECT @"LOBBY_MEMBER_CONNECT"
#define LOBBY_MEMBER_DISCONNECT @"LOBBY_MEMBER_DISCONNECT"
#define LOBBY_MEMBER_UPDATE @"LOBBY_MEMBER_UPDATE"
#define LOBBY_MESSAGE @"LOBBY_MESSAGE"
#define LOBBY_UPDATE @"LOBBY_UPDATE"
#define LOBBY_VOICE_SERVER_UPDATE @"LOBBY_VOICE_SERVER_UPDATE"
#define LOBBY_VOICE_STATE_UPDATE @"LOBBY_VOICE_STATE_UPDATE"
#define MESSAGE_ACK @"MESSAGE_ACK"
#define MESSAGE_CREATE @"MESSAGE_CREATE"
#define MESSAGE_DELETE @"MESSAGE_DELETE"
#define MESSAGE_DELETE_BULK @"MESSAGE_DELETE_BULK"
#define MESSAGE_REACTION_ADD @"MESSAGE_REACTION_ADD"
#define MESSAGE_REACTION_ADD_MANY @"MESSAGE_REACTION_ADD_MANY"
#define MESSAGE_REACTION_REMOVE @"MESSAGE_REACTION_REMOVE"
#define MESSAGE_REACTION_REMOVE_ALL @"MESSAGE_REACTION_REMOVE_ALL"
#define MESSAGE_REACTION_REMOVE_EMOJI @"MESSAGE_REACTION_REMOVE_EMOJI"
#define MESSAGE_UPDATE @"MESSAGE_UPDATE"
#define NOTIFICATION_CENTER_ITEM_COMPLETED @"NOTIFICATION_CENTER_ITEM_COMPLETED"
#define NOTIFICATION_CENTER_ITEM_CREATE @"NOTIFICATION_CENTER_ITEM_CREATE"
#define NOTIFICATION_CENTER_ITEM_DELETE @"NOTIFICATION_CENTER_ITEM_DELETE"
#define NOTIFICATION_CENTER_ITEMS_ACK @"NOTIFICATION_CENTER_ITEMS_ACK"
#define OAUTH2_TOKEN_REVOKE @"OAUTH2_TOKEN_REVOKE"
#define PASSIVE_UPDATE_V1 @"PASSIVE_UPDATE_V1"
#define PAYMENT_UPDATE @"PAYMENT_UPDATE"
#define PRESENCE_UPDATE_EVENT @"PRESENCE_UPDATE"
#define PRESENCES_REPLACE @"PRESENCES_REPLACE"
#define PRIVATE_CHANNEL_INTEGRATION_CREATE @"PRIVATE_CHANNEL_INTEGRATION_CREATE"
#define PRIVATE_CHANNEL_INTEGRATION_DELETE @"PRIVATE_CHANNEL_INTEGRATION_DELETE"
#define PRIVATE_CHANNEL_INTEGRATION_UPDATE @"PRIVATE_CHANNEL_INTEGRATION_UPDATE"
#define READY @"READY"
#define READY_SUPPLEMENTAL @"READY_SUPPLEMENTAL"
#define RECENT_MENTION_DELETE @"RECENT_MENTION_DELETE"
#define RELATIONSHIP_ADD @"RELATIONSHIP_ADD"
#define RELATIONSHIP_REMOVE @"RELATIONSHIP_REMOVE"
#define RELATIONSHIP_UPDATE @"RELATIONSHIP_UPDATE"
#define RESUMED @"RESUMED"
#define SESSIONS_REPLACE @"SESSIONS_REPLACE"
#define SOUNDBOARD_SOUNDS @"SOUNDBOARD_SOUNDS"
#define SPEED_TEST_CREATE_EVENT @"SPEED_TEST_CREATE"
#define SPEED_TEST_DELETE_EVENT @"SPEED_TEST_DELETE"
#define SPEED_TEST_SERVER_UPDATE @"SPEED_TEST_SERVER_UPDATE"
#define SPEED_TEST_UPDATE @"SPEED_TEST_UPDATE"
#define STAGE_INSTANCE_CREATE @"STAGE_INSTANCE_CREATE"
#define STAGE_INSTANCE_DELETE @"STAGE_INSTANCE_DELETE"
#define STAGE_INSTANCE_UPDATE @"STAGE_INSTANCE_UPDATE"
#define STREAM_CREATE_EVENT @"STREAM_CREATE"
#define STREAM_DELETE_EVENT @"STREAM_DELETE"
#define STREAM_SERVER_UPDATE @"STREAM_SERVER_UPDATE"
#define STREAM_UPDATE @"STREAM_UPDATE"
#define THREAD_CREATE @"THREAD_CREATE"
#define THREAD_DELETE @"THREAD_DELETE"
#define THREAD_LIST_SYNC @"THREAD_LIST_SYNC"
#define THREAD_MEMBER_LIST_UPDATE @"THREAD_MEMBER_LIST_UPDATE"
#define THREAD_MEMBER_UPDATE @"THREAD_MEMBER_UPDATE"
#define THREAD_MEMBERS_UPDATE @"THREAD_MEMBERS_UPDATE"
#define THREAD_UPDATE @"THREAD_UPDATE"
#define TYPING_START @"TYPING_START"
#define USER_ACHIEVEMENT_UPDATE @"USER_ACHIEVEMENT_UPDATE"
#define USER_CONNECTIONS_LINK_CALLBACK @"USER_CONNECTIONS_LINK_CALLBACK"
#define USER_CONNECTIONS_UPDATE @"USER_CONNECTIONS_UPDATE"
#define USER_GUILD_SETTINGS_UPDATE @"USER_GUILD_SETTINGS_UPDATE"
#define USER_NON_CHANNEL_ACK @"USER_NON_CHANNEL_ACK"
#define USER_NOTE_UPDATE @"USER_NOTE_UPDATE"
#define USER_PAYMENT_CLIENT_ADD @"USER_PAYMENT_CLIENT_ADD"
#define USER_PAYMENT_SOURCES_UPDATE @"USER_PAYMENT_SOURCES_UPDATE"
#define USER_PREMIUM_GUILD_SUBSCRIPTION_SLOT_CREATE @"USER_PREMIUM_GUILD_SUBSCRIPTION_SLOT_CREATE"
#define USER_PREMIUM_GUILD_SUBSCRIPTION_SLOT_UPDATE @"USER_PREMIUM_GUILD_SUBSCRIPTION_SLOT_UPDATE"
#define USER_REQUIRED_ACTION_UPDATE @"USER_REQUIRED_ACTION_UPDATE"
#define USER_SETTINGS_PROTO_UPDATE @"USER_SETTINGS_PROTO_UPDATE"
#define USER_SUBSCRIPTIONS_UPDATE @"USER_SUBSCRIPTIONS_UPDATE"
#define USER_UPDATE @"USER_UPDATE"
#define VOICE_CHANNEL_EFFECT_SEND @"VOICE_CHANNEL_EFFECT_SEND"
#define VOICE_SERVER_UPDATE @"VOICE_SERVER_UPDATE"
#define VOICE_STATE_UPDATE_EVENT @"VOICE_STATE_UPDATE"
#define CHANNEL_UNREAD_UPDATE @"CHANNEL_UNREAD_UPDATE"

@interface DCServerCommunicator : NSObject<UIAlertViewDelegate>

@property (strong, nonatomic) WSWebSocket* websocket;
@property (strong, nonatomic) NSString* token;
@property (assign, nonatomic) BOOL dataSaver;
@property (strong, nonatomic) DCUserInfo* currentUserInfo;
@property (strong, nonatomic) NSString* gatewayURL;
@property (strong, nonatomic) NSMutableDictionary* userChannelSettings;

@property (strong, nonatomic) DCSnowflake* snowflake;

@property (strong, nonatomic) NSMutableArray* guilds;
@property (assign, nonatomic) BOOL guildsIsSorted;
@property (strong, nonatomic) NSMutableDictionary* channels;
@property (strong, nonatomic) NSMutableDictionary* loadedUsers;
@property (strong, nonatomic) NSMutableDictionary* loadedRoles;
@property (strong, nonatomic) NSMutableDictionary* loadedEmojis;

@property (strong, nonatomic) DCGuild* selectedGuild;
@property (strong, nonatomic) DCChannel* selectedChannel;

@property (assign, nonatomic) BOOL didAuthenticate;

+ (DCServerCommunicator*)sharedInstance;
- (void)description;
- (void)startCommunicator;
- (void)reconnect;
- (void)sendHeartbeat:(NSTimer*)timer;
- (void)sendJSON:(NSDictionary*)dictionary;
- (void)sendGuildSubscriptionWithGuildId:(NSString*)guildId channelId:(NSString*)channelId;

@end
