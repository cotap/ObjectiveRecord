// CoreDataManager.m
//
// Copyright (c) 2014 Marin Usalj <http://supermar.in>
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import "CoreDataManager.h"

@implementation CoreDataManager
@synthesize managedObjectContext = _managedObjectContext;
@synthesize managedObjectModel = _managedObjectModel;
@synthesize persistentStoreCoordinator = _persistentStoreCoordinator;
@synthesize databaseStorageDirectory = _databaseStorageDirectory;
@synthesize databaseName = _databaseName;
@synthesize modelName = _modelName;
@synthesize modelSubdirectory = _modelSubdirectory;

+ (id)instance {
    return [self sharedManager];
}

+ (instancetype)sharedManager {
    static CoreDataManager *singleton;
    static dispatch_once_t singletonToken;
    dispatch_once(&singletonToken, ^{
        singleton = [[self alloc] init];
    });
    return singleton;
}


#pragma mark - Private

- (NSString *)appName {
    return [[NSBundle bundleForClass:[self class]] infoDictionary][@"CFBundleName"];
}

- (NSURL *)databaseStorageDirectory {
    if (_databaseStorageDirectory != nil) return _databaseStorageDirectory;
    return [self isOSX] ? self.applicationSupportDirectory : self.applicationDocumentsDirectory;
}

- (NSString *)databaseName {
    if (_databaseName != nil) return _databaseName;

    _databaseName = [[[self appName] stringByAppendingString:@".sqlite"] copy];
    return _databaseName;
}

- (NSString *)modelName {
    if (_modelName != nil) return _modelName;

    _modelName = [[self appName] copy];
    return _modelName;
}


#pragma mark - Public

- (NSManagedObjectContext *)managedObjectContext {
    if (_managedObjectContext) return _managedObjectContext;

    if (self.persistentStoreCoordinator) {
        _managedObjectContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
        [_managedObjectContext setPersistentStoreCoordinator:self.persistentStoreCoordinator];
    }
    return _managedObjectContext;
}

- (NSManagedObjectModel *)managedObjectModel {
    if (_managedObjectModel) return _managedObjectModel;

    NSURL *modelURL = [NSBundle.mainBundle URLForResource:[self modelName] withExtension:@"momd" subdirectory:self.modelSubdirectory];
    _managedObjectModel = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL];
    return _managedObjectModel;
}

- (NSPersistentStoreCoordinator *)persistentStoreCoordinator {
    if (_persistentStoreCoordinator) return _persistentStoreCoordinator;

    _persistentStoreCoordinator = [self persistentStoreCoordinatorWithStoreType:NSSQLiteStoreType
                                                                       storeURL:[self sqliteStoreURL]];
    return _persistentStoreCoordinator;
}

- (void)migrateDatabaseToNewManager:(CoreDataManager *)newManager {
    NSPersistentStoreCoordinator *coordinator = self.persistentStoreCoordinator;
    NSPersistentStore *sourceStore = coordinator.persistentStores.firstObject;
    
    
    NSURL *destFile = newManager.sqliteStoreURL;
    NSError *error = nil;
    [self.persistentStoreCoordinator migratePersistentStore:sourceStore toURL: destFile options:nil withType:NSSQLiteStoreType error:&error];
    if (error != nil) {
        NSLog(@"Faild to move database to shared container %@", error);
        return;
    }
    NSURL *dataStoreDirectory = self.sqliteStoreURL.URLByDeletingLastPathComponent;
    [[NSFileManager defaultManager] removeItemAtURL:dataStoreDirectory error:&error];
    if (error != nil) {
        NSLog(@"Failed to remove folder at path %@ %@", dataStoreDirectory, error);
        return;
    }
}

- (void)useInMemoryStore {
    _persistentStoreCoordinator = [self persistentStoreCoordinatorWithStoreType:NSInMemoryStoreType storeURL:nil];
}

- (BOOL)saveContext {
    if (self.managedObjectContext == nil) return NO;
    if (![self.managedObjectContext hasChanges])return NO;

    NSError *error = nil;

    if (![self.managedObjectContext save:&error]) {
        NSLog(@"Unresolved error in saving context! %@, %@", error, [error userInfo]);
        return NO;
    }

    return YES;
}


#pragma mark - SQLite file directory

- (NSURL *)applicationDocumentsDirectory {
    return [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory
                                                   inDomains:NSUserDomainMask] lastObject];
}

- (NSURL *)applicationSupportDirectory {
    return [[[[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory
                                                   inDomains:NSUserDomainMask] lastObject]
            URLByAppendingPathComponent:[self appName]];
}

- (NSURL *)sharedContainerURLWithIdentifier:(NSString *)groupId {
    return [[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier: groupId];
}


#pragma mark - Private

- (NSPersistentStoreCoordinator *)persistentStoreCoordinatorWithStoreType:(NSString *const)storeType
                                                                 storeURL:(NSURL *)storeURL {

    NSPersistentStoreCoordinator *coordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:[self managedObjectModel]];

    NSDictionary *options = @{ NSMigratePersistentStoresAutomaticallyOption: @YES,
                               NSInferMappingModelAutomaticallyOption: @YES };

    NSError *error = nil;
    if (![coordinator addPersistentStoreWithType:storeType configuration:nil URL:storeURL options:options error:&error])
        NSLog(@"ERROR WHILE CREATING PERSISTENT STORE COORDINATOR! %@, %@", error, [error userInfo]);

    return coordinator;
}

- (NSURL *)sqliteStoreURL {
    NSURL *directory = self.databaseStorageDirectory;
    NSURL *databaseDir = [directory URLByAppendingPathComponent:[self databaseName]];

    [self createApplicationSupportDirIfNeeded:directory];
    return databaseDir;
}

- (BOOL)isOSX {
    if (NSClassFromString(@"UIDevice")) return NO;
    return YES;
}

- (void)createApplicationSupportDirIfNeeded:(NSURL *)url {
    if ([[NSFileManager defaultManager] fileExistsAtPath:url.absoluteString]) return;

    [[NSFileManager defaultManager] createDirectoryAtURL:url
                             withIntermediateDirectories:YES attributes:nil error:nil];
}

@end
