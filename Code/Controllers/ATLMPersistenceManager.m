//
//  ATLMPersistenceManager.m
//  Atlas Messenger
//
//  Created by Blake Watters on 6/28/14.
//  Copyright (c) 2014 Layer, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import "ATLMPersistenceManager.h"
#import "ATLMUtilities.h"

#define ATLMMustBeImplementedBySubclass() @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"Must be implemented by concrete subclass." userInfo:nil]

static NSString *const ATLMOnDiskPersistenceManagerUsersFileName = @"Users.plist";
static NSString *const ATLMOnDiskPersistenceManagerSessionFileName = @"Session.plist";

@interface ATLMPersistenceManager ()

@property (nonatomic) NSSet *users;
@property (nonatomic) ATLMSession *session;

@end

@interface ATLMInMemoryPersistenceManager : ATLMPersistenceManager

@end

@interface ATLMOnDiskPersistenceManager : ATLMPersistenceManager

@property (nonatomic, readonly) NSString *path;

- (id)initWithPath:(NSString *)path;

@end

@implementation ATLMPersistenceManager

+ (instancetype)defaultManager
{
    if (ATLMIsRunningTests()) {
        return [ATLMPersistenceManager persistenceManagerWithInMemoryStore];
    }
    return [ATLMPersistenceManager persistenceManagerWithStoreAtPath:[ATLMApplicationDataDirectory() stringByAppendingPathComponent:@"PersistentObjects"]];
}

+ (instancetype)persistenceManagerWithInMemoryStore
{
    return [ATLMInMemoryPersistenceManager new];
}

+ (instancetype)persistenceManagerWithStoreAtPath:(NSString *)path
{
    return [[ATLMOnDiskPersistenceManager alloc] initWithPath:path];
}

- (id)init
{
    if ([self isMemberOfClass:[ATLMPersistenceManager class]]) {
        @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"Failed to call designated initializer." userInfo:nil];
    } else {
        return [super init];
    }
}

- (BOOL)persistUsers:(NSSet *)users error:(NSError **)error
{
    ATLMMustBeImplementedBySubclass();
}

- (NSSet *)persistedUsersWithError:(NSError **)error
{
    ATLMMustBeImplementedBySubclass();
}

- (BOOL)deleteAllObjects:(NSError **)error
{
    ATLMMustBeImplementedBySubclass();
}

- (BOOL)persistSession:(ATLMSession *)session error:(NSError **)error
{
    ATLMMustBeImplementedBySubclass();
}

- (ATLMSession *)persistedSessionWithError:(NSError **)error
{
    ATLMMustBeImplementedBySubclass();
}

- (void)performUserSearchWithString:(NSString *)searchString completion:(void (^)(NSArray *users, NSError *error))completion
{
    NSError *error;
    NSSet *users = [self persistedUsersWithError:&error];
    if (error) {
        completion(nil, error);
    } else {
        NSPredicate *searchPredicate = [self predicateForUsersWithSearchString:searchString];
        completion([users filteredSetUsingPredicate:searchPredicate].allObjects, nil);
    }
}

- (NSSet *)usersForIdentifiers:(NSSet *)identifiers;
{
    NSError *error;
    NSSet *allUsers = [self persistedUsersWithError:&error];
    if (error) return nil;

    NSPredicate *searchPredicate = [NSPredicate predicateWithFormat:@"SELF.userID IN %@", identifiers];
    NSSet *users = [allUsers filteredSetUsingPredicate:searchPredicate];
    return users;
}

- (ATLMUser *)userForIdentifier:(NSString *)identifier
{
    NSError *error;
    NSSet *allUsers = [self persistedUsersWithError:&error];
    if (error) return nil;
    
    for (ATLMUser *user in allUsers) {
        if ([user.userID isEqualToString:identifier]) {
            return user;
        }
    }
    return nil;
}

#pragma mark - Helpers

- (NSPredicate *)predicateForUsersWithSearchString:(NSString *)searchString
{
    NSString *escapedSearchString = [NSRegularExpression escapedPatternForString:searchString];
    NSString *searchPattern = [NSString stringWithFormat:@".*\\b%@.*", escapedSearchString];
    NSPredicate *searchPredicate = [NSPredicate predicateWithFormat:@"fullName MATCHES[cd] %@", searchPattern];
    return searchPredicate;
}

@end

@implementation ATLMInMemoryPersistenceManager

- (BOOL)persistUsers:(NSSet *)users error:(NSError **)error
{
    NSParameterAssert(users);
    self.users = users;
    return YES;
}

- (NSSet *)persistedUsersWithError:(NSError **)error
{
    return self.users;
}

- (BOOL)persistSession:(ATLMSession *)session error:(NSError **)error
{
    self.session = session;
    return YES;
}

- (ATLMSession *)persistedSessionWithError:(NSError **)error
{
    return self.session;
}

- (BOOL)deleteAllObjects:(NSError **)error
{
    self.users = nil;
    self.session = nil;
    return YES;
}

@end

@implementation ATLMOnDiskPersistenceManager

- (id)initWithPath:(NSString *)path
{
    self = [super init];
    if (self) {
        _path = path;
        
        NSFileManager *fileManager = [NSFileManager defaultManager];
        BOOL isDirectory;
        if ([fileManager fileExistsAtPath:path isDirectory:&isDirectory]) {
            if (!isDirectory) {
                [NSException raise:NSInternalInconsistencyException format:@"Failed to initialize persistent store at '%@': specified path is a regular file.", path];
            }
        } else {
            NSError *error;
            BOOL success = [fileManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:&error];
            if (!success) {
                [NSException raise:NSInternalInconsistencyException format:@"Failed creating persistent store at '%@': %@", path, error];
            }
        }
    }
    return self;
}

- (BOOL)persistUsers:(NSSet *)users error:(NSError **)error
{
    NSString *path = [self usersPath];
    NSLog(@"users: %@, toFile: %@", users, path);
    if (![NSKeyedArchiver archiveRootObject:users toFile:path]) return NO;
    self.users = users;
    return YES;
}

- (NSSet *)persistedUsersWithError:(NSError **)error
{
    if (self.users) return self.users;
    
    NSString *path = [self usersPath];
    NSSet *users = [NSKeyedUnarchiver unarchiveObjectWithFile:path];
    self.users = users;
    return users;
}

- (BOOL)deleteAllObjects:(NSError **)error
{
    NSFileManager *fileManager = [NSFileManager defaultManager];

    if (![fileManager removeItemAtPath:[self usersPath] error:error]) return NO;
    self.users = nil;

    if (![fileManager removeItemAtPath:[self sessionPath] error:error]) return NO;
    self.session = nil;
    
    return YES;
}

- (BOOL)persistSession:(ATLMSession *)session error:(NSError **)error
{
    NSString *path = [self sessionPath];
    self.session = session;
    return [NSKeyedArchiver archiveRootObject:session toFile:path];
}

- (ATLMSession *)persistedSessionWithError:(NSError **)error
{
    if (self.session) return self.session;

    NSString *path = [self sessionPath];
    ATLMSession *session = [NSKeyedUnarchiver unarchiveObjectWithFile:path];
    self.session = session;
    return session;
}

#pragma mark - Helpers

- (NSString *)usersPath
{
    return [self.path stringByAppendingPathComponent:ATLMOnDiskPersistenceManagerUsersFileName];
}

- (NSString *)sessionPath
{
    return [self.path stringByAppendingPathComponent:ATLMOnDiskPersistenceManagerSessionFileName];
}

@end
